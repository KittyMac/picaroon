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

    private static let fileSuffix = ".delivery.data"

    private let baseRetryInterval: TimeInterval = 1.0
    private let maxRetryInterval: TimeInterval = 300.0
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60

    // Job bookkeeping is keyed by record id, not by file url, so that a job's
    // identity survives a change to storageURL. fileURLs is the authoritative
    // record of where a job actually lives on disk; it is NOT recomputed from
    // the current storageURL, because a job persisted before a reconfigure
    // still lives in the old directory.
    private var pendingIDs: [String] = []       // FIFO queue of ids awaiting delivery
    private var pendingSet: Set<String> = []    // membership index for pendingIDs
    private var inflightIDs: Set<String> = []   // ids with a request currently in flight
    private var fileURLs: [String: URL] = [:]   // id -> actual on-disk location

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

        // the encode/encrypt/compress/write is deliberately done on the caller's
        // thread rather than on the actor
        let fileUrl: URL
        do {
            fileUrl = try persist(record)
        } catch {
            returnCallback(nil, nil, "failed to persist delivery \(record.id): \(error)")
            return
        }
        
        // important because this can be called from off of the actor.
        // Registering the callback and enqueuing the job happen in the same
        // message so there is never a window in which the job is deliverable
        // but its callback is not yet known.
        unsafeSend { _ in
            self.outstandingCallbacks[record.id] = returnCallback
            self.enqueue(id: record.id, fileUrl: fileUrl)

            self.checkForMore()
        }
    }

    // MARK: - job bookkeeping (actor-private)

    private func enqueue(id: String, fileUrl: URL) {
        fileURLs[id] = fileUrl

        // a job that is currently being delivered must not be queued a second
        // time, otherwise it would be delivered twice
        guard inflightIDs.contains(id) == false else { return }
        guard pendingSet.contains(id) == false else { return }

        pendingSet.insert(id)
        pendingIDs.append(id)
    }

    private func dequeue() -> (id: String, fileUrl: URL)? {
        while pendingIDs.isEmpty == false {
            let id = pendingIDs.removeFirst()
            pendingSet.remove(id)

            if let fileUrl = fileURLs[id] {
                return (id, fileUrl)
            }

            // we no longer know where this job lives, so it can never be
            // delivered; report it instead of dropping it silently
            complete(id: id, data: nil, response: nil, error: "delivery lost")
        }
        return nil
    }

    /// Terminal state for a job: remove it from all tracking, delete its file
    /// from wherever it actually lives, and invoke its callback exactly once.
    private func complete(id: String,
                          data: Data?,
                          response: HTTPURLResponse?,
                          error: String?) {
        inflightIDs.remove(id)
        if pendingSet.remove(id) != nil {
            pendingIDs.removeAll { $0 == id }
        }

        if let fileUrl = fileURLs.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: fileUrl)
        }

        // jobs recovered from a previous process run have no callback; that is
        // expected and is not an error
        if let callback = outstandingCallbacks.removeValue(forKey: id) {
            callback(data, response, error)
        }
    }

    // MARK: -

    private func checkForMore() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        while outstandingRequests < maxConcurrentRequests {
            guard let (id, fileUrl) = dequeue() else { return }
            
            guard let data = try? Data(contentsOf: fileUrl),
                  let decompressed = try? decrypt(data.gunzipped()),
                  let record = try? decoder.decode(DeliveryRecord.self, from: decompressed) else {
                // the file is gone, corrupt, or was written with a different
                // encryption key. It can never be delivered, so retire it
                // rather than leaking the file and stranding the callback.
                complete(id: id, data: nil, response: nil, error: "delivery unreadable")
                continue
            }
            if isExpired(record) {
                complete(id: id, data: nil, response: nil, error: "delivery expired")
                continue
            }
            
            let decompressedBody = (try? record.body?.gunzipped()) ?? record.body
            
            outstandingRequests += 1
            inflightIDs.insert(id)
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

                // must happen before any enqueue, since enqueue ignores
                // ids that are still in flight
                self.inflightIDs.remove(id)
                
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
                    self.complete(id: id, data: data, response: response, error: error)
                    return
                }
                                
                if self.isExpired(record) {
                    // print("expiring \(record.id)")
                    self.complete(id: id, data: data, response: response, error: "delivery expired")
                    return
                }
                
                // print("retry \(record.id)")
                self.enqueue(id: id, fileUrl: fileUrl)
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
        return storageURL.appendingPathComponent("\(id)\(Self.fileSuffix)", isDirectory: false)
    }

    private func recordID(for fileUrl: URL) -> String? {
        let name = fileUrl.lastPathComponent
        guard name.hasSuffix(Self.fileSuffix) else { return nil }
        let id = String(name.dropLast(Self.fileSuffix.count))
        guard id.isEmpty == false else { return nil }
        return id
    }

    private func persist(_ record: DeliveryRecord) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let fileUrl = fileURL(for: record.id)
        let data = encrypt(try encoder.encode(record))
        let compressed = try data.gzipped(level: .bestCompression)
        try compressed.write(to: fileUrl, options: .atomic)
        return fileUrl
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

        // additive only: enqueue() dedupes against jobs we already have queued
        // or in flight, so calling this again mid-run cannot duplicate or drop
        // work
        for file in files {
            guard let id = recordID(for: file) else { continue }
            enqueue(id: id, fileUrl: file)
        }
    }
}
