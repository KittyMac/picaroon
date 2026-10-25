import Foundation
import Flynn
import Gzip

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - S3 Inventory parsing

/// The parts of an S3 Inventory manifest.json needed to read its CSV data files.
internal struct S3InventoryManifest {
    let creationDate: Date
    let dataFileKeys: [String]
    let keyColumn: Int
    let sizeColumn: Int?
    let lastModifiedColumn: Int?
    
    init?(json data: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (json["fileFormat"] as? String)?.uppercased() == "CSV",
              let schema = json["fileSchema"] as? String,
              let files = json["files"] as? [[String: Any]] else {
            return nil
        }
        
        // creationTimestamp is milliseconds since 1970, sent as a string
        guard let creationString = json["creationTimestamp"] as? String,
              let creationMs = Double(creationString) else {
            return nil
        }
        
        // e.g. "Bucket, Key, Size, LastModifiedDate"
        let columns = schema.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyColumn = columns.firstIndex(of: "Key") else { return nil }
        
        self.creationDate = Date(timeIntervalSince1970: creationMs / 1000.0)
        self.dataFileKeys = files.compactMap { $0["key"] as? String }
        self.keyColumn = keyColumn
        self.sizeColumn = columns.firstIndex(of: "Size")
        self.lastModifiedColumn = columns.firstIndex(of: "LastModifiedDate")
    }
}

internal struct S3InventoryEntry {
    let key: String
    let size: Int64
    let modifiedDate: Date
}

private let asciiQuote = UInt8(ascii: "\"")
private let asciiComma = UInt8(ascii: ",")
private let asciiNewline = UInt8(ascii: "\n")
private let asciiReturn = UInt8(ascii: "\r")
private let asciiPercent = UInt8(ascii: "%")
private let asciiZero = UInt8(ascii: "0")
private let asciiNine = UInt8(ascii: "9")

/// True when every byte of the string reads the same URL-encoded or not, so it can be
/// compared against the raw (still encoded) keys in an inventory CSV.
private func isUrlEncodingInvariant(_ string: String) -> Bool {
    for c in string.utf8 {
        switch c {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."),
             UInt8(ascii: "~"), UInt8(ascii: "/"):
            continue
        default:
            return false
        }
    }
    return true
}

private func hexValue(_ c: UInt8) -> UInt8? {
    switch c {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
    default: return nil
    }
}

/// Keys in CSV inventories are URL-encoded. Only %XX sequences are decoded: a literal
/// "+" is left alone, since S3 keys may legitimately contain "+".
private func inventoryKey(_ bytes: UnsafeRawBufferPointer, _ start: Int, _ end: Int) -> String {
    let field = UnsafeRawBufferPointer(rebasing: bytes[start..<end])
    guard field.contains(asciiPercent) else {
        return String(decoding: field, as: UTF8.self)
    }
    var decoded: [UInt8] = []
    decoded.reserveCapacity(field.count)
    var i = 0
    while i < field.count {
        if field[i] == asciiPercent,
           i + 2 < field.count,
           let hi = hexValue(field[i + 1]),
           let lo = hexValue(field[i + 2]) {
            decoded.append(hi << 4 | lo)
            i += 3
        } else {
            decoded.append(field[i])
            i += 1
        }
    }
    return String(decoding: decoded, as: UTF8.self)
}

private func inventoryInt(_ bytes: UnsafeRawBufferPointer, _ start: Int, _ end: Int) -> Int64? {
    guard start < end else { return nil }
    var value: Int64 = 0
    for i in start..<end {
        let c = bytes[i]
        guard c >= asciiZero && c <= asciiNine else { return nil }
        value = value * 10 + Int64(c - asciiZero)
    }
    return value
}

/// Parses "2026-09-20T08:13:31.000Z" (the only form S3 uses) without a DateFormatter.
private func inventoryTimestamp(_ bytes: UnsafeRawBufferPointer, _ start: Int, _ end: Int) -> Date? {
    let count = end - start
    guard count >= 20 else { return nil }
    func at(_ i: Int) -> UInt8 { return bytes[start + i] }
    guard at(4) == UInt8(ascii: "-"), at(7) == UInt8(ascii: "-"), at(10) == UInt8(ascii: "T"),
          at(13) == UInt8(ascii: ":"), at(16) == UInt8(ascii: ":") else { return nil }
    
    func number(_ offset: Int, _ length: Int) -> Int? {
        var value = 0
        for i in offset..<(offset + length) {
            let c = at(i)
            guard c >= asciiZero && c <= asciiNine else { return nil }
            value = value * 10 + Int(c - asciiZero)
        }
        return value
    }
    
    guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
          let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
          month >= 1, month <= 12, day >= 1, day <= 31, hour <= 23, minute <= 59, second <= 60 else { return nil }
    
    var index = 19
    var fraction = 0.0
    if at(index) == UInt8(ascii: ".") {
        index += 1
        var scale = 0.1
        while index < count, at(index) >= asciiZero, at(index) <= asciiNine {
            fraction += Double(at(index) - asciiZero) * scale
            scale /= 10
            index += 1
        }
    }
    guard index == count - 1, at(index) == UInt8(ascii: "Z") else { return nil }
    
    // Days since 1970-01-01 (Howard Hinnant's days_from_civil)
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (month + 9) % 12
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    let days = era * 146097 + doe - 719468
    
    return Date(timeIntervalSince1970: Double(days * 86400 + hour * 3600 + minute * 60 + second) + fraction)
}

/// Returns the rows of one inventory CSV data file (already decompressed) whose key
/// starts with keyPrefix. Rows are compared on their raw bytes and only matching rows
/// become Strings, so scanning a multi-million row file mostly just walks memory.
internal func parseS3InventoryCSV(_ data: Data,
                                  manifest: S3InventoryManifest,
                                  keyPrefix: String) -> [S3InventoryEntry] {
    var entries: [S3InventoryEntry] = []
    
    let prefixBytes = Array(keyPrefix.utf8)
    let comparePrefixRaw = isUrlEncodingInvariant(keyPrefix)
    let lastNeededColumn = max(manifest.keyColumn, manifest.sizeColumn ?? 0, manifest.lastModifiedColumn ?? 0)
    
    var fieldStarts = [Int](repeating: 0, count: lastNeededColumn + 1)
    var fieldEnds = [Int](repeating: 0, count: lastNeededColumn + 1)
    
    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        guard let base = bytes.baseAddress else { return }
        let total = bytes.count
        var lineStart = 0
        
        while lineStart < total {
            // memchr is far faster than a byte loop over hundreds of MB
            let lineEndAbsolute: Int
            if let found = memchr(base + lineStart, Int32(asciiNewline), total - lineStart) {
                lineEndAbsolute = base.distance(to: UnsafeRawPointer(found))
            } else {
                lineEndAbsolute = total
            }
            let nextLine = lineEndAbsolute + 1
            var lineEnd = lineEndAbsolute
            if lineEnd > lineStart && bytes[lineEnd - 1] == asciiReturn {
                lineEnd -= 1
            }
            
            // Split out the fields we need. Values are URL-encoded, so a quoted value
            // can never contain a quote or a comma.
            var column = 0
            var i = lineStart
            var key: String? = nil
            var rejected = false
            while i <= lineEnd && column <= lastNeededColumn {
                var start = i
                var end: Int
                if i < lineEnd && bytes[i] == asciiQuote {
                    start = i + 1
                    end = start
                    while end < lineEnd && bytes[end] != asciiQuote { end += 1 }
                    i = end + 1
                    while i < lineEnd && bytes[i] != asciiComma { i += 1 }
                } else {
                    end = i
                    while end < lineEnd && bytes[end] != asciiComma { end += 1 }
                    i = end
                }
                fieldStarts[column] = start
                fieldEnds[column] = end
                
                // Decide on the key as soon as it is read, so the large majority of
                // rows (other days and folders) are skipped without parsing further.
                if column == manifest.keyColumn {
                    if comparePrefixRaw {
                        if end - start >= prefixBytes.count,
                           memcmp(base + start, prefixBytes, prefixBytes.count) == 0 {
                            key = inventoryKey(bytes, start, end)
                        }
                    } else {
                        let decoded = inventoryKey(bytes, start, end)
                        if decoded.hasPrefix(keyPrefix) {
                            key = decoded
                        }
                    }
                    // Skip non-matching rows and "folder" placeholder keys, as listing does
                    if key == nil || key!.hasSuffix("/") {
                        rejected = true
                        break
                    }
                }
                
                column += 1
                i += 1
            }
            
            if rejected == false, column > lastNeededColumn, let key = key {
                var size: Int64 = 0
                if let column = manifest.sizeColumn {
                    size = inventoryInt(bytes, fieldStarts[column], fieldEnds[column]) ?? 0
                }
                var modifiedDate = Date.distantPast
                if let column = manifest.lastModifiedColumn {
                    modifiedDate = inventoryTimestamp(bytes, fieldStarts[column], fieldEnds[column]) ?? .distantPast
                }
                entries.append(S3InventoryEntry(key: key, size: size, modifiedDate: modifiedDate))
            }
            
            lineStart = nextLine
        }
    }
    
    return entries
}

// MARK: - Sync using an inventory

fileprivate func walkLocalFilesForInventory(localDirectoryUrl: URL,
                                            keyPrefix: String) -> [String: LocalFile] {
    var filesByS3Key: [String: LocalFile] = [:]
    let localDirectoryPath = localDirectoryUrl.path
    
    if let enumerator = FileManager.default.enumerator(at: localDirectoryUrl,
                                                       includingPropertiesForKeys: [.isRegularFileKey],
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set([.isRegularFileKey])) else { continue }
            guard resourceValues.isRegularFile == true else { continue }
            
            let path = fileURL.path
            
            // Same key construction as beSyncToLocal
            guard let relativePath = path.components(separatedBy: localDirectoryPath).last else { continue }
            var s3Key = keyPrefix + relativePath
            s3Key = s3Key.replacingOccurrences(of: "//", with: "/")
            
            filesByS3Key[s3Key] = LocalFile(name: fileURL.lastPathComponent,
                                            path: path,
                                            s3Key: s3Key)
        }
    }
    return filesByS3Key
}

extension HTTPSession {
    
    /// Like beSyncToLocal(continuous: false), but takes the list of objects from the newest
    /// S3 Inventory report under inventoryPrefix instead of listing the bucket.
    ///
    /// - inventoryPrefix: the folder holding the inventory configuration's reports, i.e. the
    ///   one containing the dated folders with manifest.json and the data/ folder
    ///   (e.g. "v1/errorlogs/staging-rover-smallplanet-com/daily_logs/").
    /// - minimumInventoryDate: fail rather than sync from a report created before this date.
    ///   For a daily folder, pass a time comfortably after the day ends, so the report
    ///   includes late uploads.
    /// - deleteLocalFilesNotInInventory: inventories are eventually consistent, so this only
    ///   ever deletes files whose modification date (set from S3 when they were downloaded)
    ///   is at least an hour older than the report.
    ///
    /// The returned continuation marker is always nil.
    public func beSyncToLocalFromInventory(credentials: S3Credentials,
                                           inventoryPrefix: String,
                                           keyPrefix: String,
                                           localDirectory: String,
                                           minimumInventoryDate: Date?,
                                           deleteLocalFilesNotInInventory: Bool,
                                           priority: HTTPSessionPriority,
                                           progressCallback: @escaping (Int, Int, Int) -> (),
                                           _ sender: Actor,
                                           _ returnCallback: @escaping ([S3Object], [S3Object], String?, String?) -> Void) {
        unsafeSend { _ in
            let localDirectoryUrl = URL(fileURLWithPath: localDirectory)
            let s3Credentials = credentials.noCloudFront()
            
            var didReturn = false
            func fail(_ error: String) {
                guard didReturn == false else { return }
                didReturn = true
                sender.unsafeSend { _ in
                    returnCallback([], [], nil, error)
                }
            }
            
            func makeRelativePath(key: String) -> String {
                var objectKey = key
                if objectKey.hasPrefix(keyPrefix) {
                    objectKey = objectKey.dropFirst(keyPrefix.count).description
                }
                if objectKey.hasPrefix("/") {
                    objectKey = objectKey.dropFirst(1).description
                }
                return objectKey
            }
            
            // The local walk runs on its own thread while the inventory is fetched.
            var localFilesByS3Key: [String: LocalFile]? = nil
            var inventoryEntries: [S3InventoryEntry]? = nil
            var inventoryDate = Date.distantPast
            
            var allObjects: [S3Object] = []
            var modifiedObjects: [S3Object] = []
            var lastError: String? = nil
            var skippedCount = 0
            var downloadCount = 0
            
            func reportProgress() {
                let skipped = skippedCount, downloaded = downloadCount, total = allObjects.count
                sender.unsafeSend { _ in
                    progressCallback(skipped, downloaded, total)
                }
            }
            
            // MARK: download missing files (runs once both the walk and the inventory are ready)
            
            func syncWhenReady() {
                guard didReturn == false,
                      let localFiles = localFilesByS3Key,
                      let entries = inventoryEntries else { return }
                
                // Same order listing would return
                let sortedEntries = entries.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
                inventoryEntries = []
                
                var pendingDownloads: [S3Object] = []
                var inventoryKeys = Set<String>()
                inventoryKeys.reserveCapacity(sortedEntries.count)
                allObjects.reserveCapacity(sortedEntries.count)
                
                for entry in sortedEntries {
                    let object = S3Object(keyPrefix: keyPrefix,
                                          key: entry.key,
                                          size: entry.size,
                                          modifiedDate: entry.modifiedDate)
                    allObjects.append(object)
                    inventoryKeys.insert(entry.key)
                    if localFiles[entry.key] == nil {
                        pendingDownloads.append(object)
                    } else {
                        skippedCount += 1
                    }
                }
                reportProgress()
                
                if deleteLocalFilesNotInInventory {
                    let cutoff = inventoryDate.addingTimeInterval(-3600)
                    for (s3Key, localFile) in localFiles where inventoryKeys.contains(s3Key) == false {
                        guard let attributes = try? FileManager.default.attributesOfItem(atPath: localFile.path),
                              let modified = attributes[.modificationDate] as? Date,
                              modified < cutoff else { continue }
                        try? FileManager.default.removeItem(atPath: localFile.path)
                    }
                }
                
                let maxDownloadsInFlight = 128
                var pendingHead = 0
                var downloadsInFlight = 0
                
                func finishIfDone() {
                    guard downloadsInFlight == 0, pendingHead >= pendingDownloads.count, didReturn == false else { return }
                    didReturn = true
                    let all = allObjects, modified = modifiedObjects, error = lastError
                    sender.unsafeSend { _ in
                        returnCallback(all, modified, nil, error)
                    }
                }
                
                func startMoreDownloads() {
                    while downloadsInFlight < maxDownloadsInFlight && pendingHead < pendingDownloads.count {
                        let object = pendingDownloads[pendingHead]
                        pendingHead += 1
                        downloadsInFlight += 1
                        
                        HTTPSessionManager.shared.beNew(priority: priority, self) { session in
                            // File IO happens on the download's own session, in parallel
                            session.beDownloadFromS3(credentials: s3Credentials,
                                                     key: object.key,
                                                     contentType: .any,
                                                     session) { data, _, _, error in
                                var wroteFile = false
                                if let data = data, error == nil {
                                    let fileUrl = localDirectoryUrl.appendingPathComponent(makeRelativePath(key: object.key))
                                    if (try? data.write(to: fileUrl)) == nil {
                                        try? FileManager.default.createDirectory(at: fileUrl.deletingLastPathComponent(),
                                                                                 withIntermediateDirectories: true)
                                        try? data.write(to: fileUrl)
                                    }
                                    try? FileManager.default.setAttributes([
                                        FileAttributeKey.creationDate: object.modifiedDate,
                                    ], ofItemAtPath: fileUrl.path)
                                    try? FileManager.default.setAttributes([
                                        FileAttributeKey.modificationDate: object.modifiedDate,
                                    ], ofItemAtPath: fileUrl.path)
                                    wroteFile = true
                                }
                                
                                self.unsafeSend { _ in
                                    if let error = error { lastError = error }
                                    if wroteFile { modifiedObjects.append(object) }
                                    downloadCount += 1
                                    downloadsInFlight -= 1
                                    reportProgress()
                                    startMoreDownloads()
                                    finishIfDone()
                                }
                            }
                        }
                    }
                }
                
                startMoreDownloads()
                finishIfDone()
            }
            
            // MARK: local walk
            
            Thread {
                let files = walkLocalFilesForInventory(localDirectoryUrl: localDirectoryUrl,
                                                       keyPrefix: keyPrefix)
                self.unsafeSend { _ in
                    localFilesByS3Key = files
                    syncWhenReady()
                }
            }.start()
            
            // MARK: inventory
            
            func loadDataFiles(_ manifest: S3InventoryManifest) {
                var collected: [S3InventoryEntry] = []
                var pendingKeys = manifest.dataFileKeys
                var filesInFlight = 0
                // Each data file is held compressed and decompressed in memory while it
                // is parsed (hundreds of MB), so only a few are processed at once.
                let maxFilesInFlight = 4
                
                func startMoreFiles() {
                    while didReturn == false && filesInFlight < maxFilesInFlight && pendingKeys.isEmpty == false {
                        let dataKey = pendingKeys.removeLast()
                        filesInFlight += 1
                        
                        HTTPSessionManager.shared.beNew(priority: priority.increment(), self) { session in
                            session.beDownloadFromS3(credentials: s3Credentials,
                                                     key: dataKey,
                                                     contentType: .any,
                                                     session) { data, _, _, error in
                                // Decompress and parse here, on the download's session
                                var entries: [S3InventoryEntry] = []
                                var fileError = error
                                if fileError == nil, let data = data {
                                    var csv = data
                                    if data.count >= 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b {
                                        if let unzipped = try? data.gunzipped() {
                                            csv = unzipped
                                        } else {
                                            fileError = "failed to decompress inventory file \(dataKey)"
                                        }
                                    }
                                    if fileError == nil {
                                        entries = parseS3InventoryCSV(csv,
                                                                      manifest: manifest,
                                                                      keyPrefix: keyPrefix)
                                    }
                                } else if fileError == nil {
                                    fileError = "failed to download inventory file \(dataKey)"
                                }
                                
                                self.unsafeSend { _ in
                                    filesInFlight -= 1
                                    if let fileError = fileError {
                                        return fail(fileError)
                                    }
                                    collected.append(contentsOf: entries)
                                    
                                    if filesInFlight == 0 && pendingKeys.isEmpty {
                                        inventoryEntries = collected
                                        collected = []
                                        syncWhenReady()
                                    } else {
                                        startMoreFiles()
                                    }
                                }
                            }
                        }
                    }
                }
                
                if pendingKeys.isEmpty {
                    inventoryEntries = []
                    syncWhenReady()
                } else {
                    startMoreFiles()
                }
            }
            
            var listPrefix = inventoryPrefix
            if listPrefix.isEmpty == false && listPrefix.hasSuffix("/") == false {
                listPrefix += "/"
            }
            
            self.beListAllKeysFromS3(credentials: credentials,
                                     keyPrefix: listPrefix,
                                     marker: nil,
                                     priority: priority.increment(),
                                     self) { objects, _, error in
                if let error = error {
                    return fail("beListAllKeysFromS3: \(error)")
                }
                
                // Reports live in folders named like 2026-10-23T01-00Z, which sort by time
                let manifestKeys = objects.map { $0.key }.filter { $0.hasSuffix("/manifest.json") }
                guard let manifestKey = manifestKeys.max(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) else {
                    return fail("no inventory manifest found under \(listPrefix)")
                }
                
                self.beDownloadFromS3(credentials: s3Credentials,
                                      key: manifestKey,
                                      contentType: .any,
                                      self) { data, _, _, error in
                    if let error = error {
                        return fail("beDownloadFromS3: \(error)")
                    }
                    guard let data = data,
                          let manifest = S3InventoryManifest(json: data) else {
                        return fail("failed to parse inventory manifest \(manifestKey)")
                    }
                    if let minimumInventoryDate = minimumInventoryDate,
                       manifest.creationDate < minimumInventoryDate {
                        return fail("newest inventory (\(manifestKey)) is older than the minimum inventory date")
                    }
                    inventoryDate = manifest.creationDate
                    loadDataFiles(manifest)
                }
            }
        }
    }
}
