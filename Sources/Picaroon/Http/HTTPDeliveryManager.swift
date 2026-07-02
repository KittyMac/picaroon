// flynn:ignore Access Level Violation: Behaviors must wrap their contents in a call to unsafeSend(

import Foundation
import Flynn
import Hitch
import Gzip

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// HTTPDeliveryManager exists to "guarantee" the eventual delivery of a result to a remote endpoint.

public class HTTPDeliveryManager: Actor {
    public static let shared = HTTPDeliveryManager()
    
    private struct DeliveryRecord: Codable {
        let id: String
        let url: String
        let httpMethod: String
        let params: [String: String]
        let headers: [String: String]
        let body: Data?
        let proxy: String?
        let createdAt: Date
    }

    private let baseRetryInterval: TimeInterval = 1.0
    private let maxRetryInterval: TimeInterval = 300.0
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private var pendingFiles: [URL] = []
    
    private var maxConcurrentRequests = 4
    private var outstandingRequests = 0
    private var outstandingCallbacks: [String:(Data?, HTTPURLResponse?, String?) -> ()] = [:]
    
    private var isConfigured = false
    private var storageURL: URL = URL(fileURLWithPath: "/tmp")
    private var encrypt: (Data) -> Data = { return $0 }
    private var decrypt: (Data) -> Data = { return $0 }
    
    public override init() {
        self.encrypt = { return $0 }
        self.decrypt = { return $0 }
        
        super.init()
        
        Flynn.Timer(timeInterval: 1.0, immediate: false, repeats: true, self) { [weak self] timer in
            guard let self = self else { return }
            self.checkForMore()
        }
    }
    
    internal func _beConfigure(storagePath: String,
                               maxConcurrentRequests: Int,
                               encrypt: ((Data) -> Data)?,
                               decrypt: ((Data) -> Data)?) {
        isConfigured = true
        
        self.storageURL = URL(fileURLWithPath: storagePath, isDirectory: true)
        self.maxConcurrentRequests = maxConcurrentRequests
        
        self.encrypt = encrypt ?? { return $0 }
        self.decrypt = decrypt ?? { return $0 }
        
        loadFromDisk()
        checkForMore()
    }
    
    public func beDeliver(url: String,
                          httpMethod: String,
                          params: [String: String],
                          headers: [String: String],
                          proxy: String?,
                          body: Data?,
                          _ sender: Actor,
                          _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> ()) {
        guard isConfigured else { return returnCallback(nil, nil, "HTTPDeliveryManager configure has not been called") }
        
        let compressedBody = (try? body?.gzipped(level: .bestSpeed)) ?? body
        
        let record = DeliveryRecord(id: UUID().uuidString,
                                    url: url,
                                    httpMethod: httpMethod,
                                    params: params,
                                    headers: headers,
                                    body: compressedBody,
                                    proxy: proxy,
                                    createdAt: Date())
        if let error = self.persist(record) {
            returnCallback(nil, nil, error)
            return
        }
        
        unsafeSend { _ in
            self.outstandingCallbacks[record.id] = returnCallback

            self.checkForMore()
        }
    }
    
    private func checkForMore() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        while outstandingRequests < maxConcurrentRequests {
            guard pendingFiles.isEmpty == false else { return }
            
            let fileUrl = pendingFiles.removeFirst()
            
            guard let data = try? Data(contentsOf: fileUrl),
                  let decompressed = try? decrypt(data.gunzipped()),
                  let record = try? decoder.decode(DeliveryRecord.self, from: decompressed) else {
                continue
            }
            if isExpired(record) {
                self.outstandingCallbacks[record.id]?(nil, nil, "delivery expired")
                self.outstandingCallbacks[record.id] = nil
                self.removeFile(for: record.id)
                continue
            }
            
            let decompressedBody = (try? record.body?.gunzipped()) ?? record.body
            
            outstandingRequests += 1
            // print("delivering \(record.body?.count ?? 0) bytes for \(record.id)")
            HTTPSession.longshot.beRequest(url: record.url,
                                           httpMethod: record.httpMethod,
                                           params: record.params,
                                           headers: record.headers,
                                           cookies: nil,
                                           timeoutRetry: 1,
                                           proxy: record.proxy,
                                           body: decompressedBody,
                                           self) { data, response, error in
                defer {
                    self.outstandingRequests -= 1
                    self.checkForMore()
                }
                
                let completionErrors: [String?] = [
                    nil,
                    "http 400",
                    "http 422",
                    "http 401",
                    "http 403",
                    "http 404",
                    "http 410",
                    "http 405",
                    "http 413",
                    "http 414",
                ]

                if completionErrors.contains(error) {
                    // print("finished \(record.id)")
                    self.outstandingCallbacks[record.id]?(data, response, error)
                    self.outstandingCallbacks[record.id] = nil
                    self.removeFile(for: record.id)
                    return
                }
                                
                if self.isExpired(record) {
                    // print("expiring \(record.id)")
                    self.outstandingCallbacks[record.id]?(data, response, "delivery expired")
                    self.outstandingCallbacks[record.id] = nil
                    self.removeFile(for: record.id)
                    return
                }
                
                // print("retry \(record.id)")
                self.pendingFiles.append(fileUrl)
            }
        }
    }

    private func isExpired(_ record: DeliveryRecord) -> Bool {
        // AWS signatures only last 15 minutes. Ideally we could regenerate the
        // signature but for now we just expire them if they get that old
        if record.headers["x-amz-storage-class"] != nil {
            return Date().timeIntervalSince(record.createdAt) > 15 * 60 * 60
        }
        
        return Date().timeIntervalSince(record.createdAt) > maxAge
    }

    private func fileURL(for id: String) -> URL {
        return storageURL.appendingPathComponent("\(id).delivery.data", isDirectory: false)
    }

    private func persist(_ record: DeliveryRecord) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let fileUrl = fileURL(for: record.id)
        do {
            let data = encrypt(try encoder.encode(record))
            let compressed = try data.gzipped(level: .bestCompression)
            try compressed.write(to: fileUrl, options: .atomic)
            
            // important because this can be called from off of the actor
            unsafeSend { _ in
                self.pendingFiles.append(fileUrl)
            }
            return nil
        } catch {
            return "failed to persist delivery \(record.id): \(error)"
        }
    }

    private func removeFile(for id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }
    
    private func loadFromDisk() {
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let files = try? FileManager.default.contentsOfDirectory(at: storageURL,
                                                                       includingPropertiesForKeys: nil) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        pendingFiles = []
        for file in files where file.lastPathComponent.hasSuffix(".delivery.data") {
            pendingFiles.append(file)
        }
    }
}
