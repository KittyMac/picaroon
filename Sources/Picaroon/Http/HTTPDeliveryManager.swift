import Foundation
import Flynn
import Hitch

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

    private final class Pending {
        enum State {
            case ready
            case inFlight
            case waiting
        }
        let record: DeliveryRecord
        var state: State
        var attempts: Int
        let returnCallback: ((Data?, HTTPURLResponse?, String?) -> ())?

        init(record: DeliveryRecord,
             state: State,
             attempts: Int,
             returnCallback: ((Data?, HTTPURLResponse?, String?) -> ())?) {
            self.record = record
            self.state = state
            self.attempts = attempts
            self.returnCallback = returnCallback
        }
    }

    private let baseRetryInterval: TimeInterval = 1.0
    private let maxRetryInterval: TimeInterval = 300.0
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private let perAttemptTimeoutRetry = 3

    private var pending: [String: Pending] = [:]
    private var readyQueue: [String] = []          // FIFO of ids whose state == .ready
    private var inFlightCount = 0
    
    private var isConfigured = false
    private var storageURL: URL = URL(fileURLWithPath: "/tmp")
    private var encrypt: (Data) -> Data = { return $0 }
    private var decrypt: (Data) -> Data = { return $0 }
    
    public override init() {
        self.encrypt = { return $0 }
        self.decrypt = { return $0 }
        
        super.init()
    }
    
    internal func _beConfigure(storagePath: String,
                               encrypt: ((Data) -> Data)?,
                               decrypt: ((Data) -> Data)?) {
        isConfigured = true
        
        self.storageURL = URL(fileURLWithPath: storagePath, isDirectory: true)
        
        self.encrypt = encrypt ?? { return $0 }
        self.decrypt = decrypt ?? { return $0 }
        
        loadFromDisk()
        unsafeSend { _ in
            self.pump()
        }
    }
    
    internal func _beDeliver(url: String,
                             httpMethod: String,
                             params: [String: String],
                             headers: [String: String],
                             proxy: String?,
                             body: Data?,
                             _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> ()) {
        guard isConfigured else { return returnCallback(nil, nil, "HTTPDeliveryManager configure has not been called") }
        
        enqueue(url: url,
                httpMethod: httpMethod,
                params: params,
                headers: headers,
                proxy: proxy,
                body: body,
                returnCallback: returnCallback)
    }

    private func enqueue(url: String,
                         httpMethod: String,
                         params: [String: String],
                         headers: [String: String],
                         proxy: String?,
                         body: Data?,
                         returnCallback: ((Data?, HTTPURLResponse?, String?) -> ())?) {
        let record = DeliveryRecord(id: UUID().uuidString,
                                    url: url,
                                    httpMethod: httpMethod,
                                    params: params,
                                    headers: headers,
                                    body: body,
                                    proxy: proxy,
                                    createdAt: Date())

        // Persist BEFORE we attempt anything. If we cannot write the record we cannot honor the
        // guarantee, so we surface that to the caller rather than pretending success.
        if let error = persist(record) {
            returnCallback?(nil, nil, error)
            return
        }

        let p = Pending(record: record, state: .ready, attempts: 0, returnCallback: returnCallback)
        pending[record.id] = p
        readyQueue.append(record.id)
        pump()
    }

    private func pump() {
        while readyQueue.isEmpty == false {
            let id = readyQueue.removeFirst()
            guard let p = pending[id], p.state == .ready else { continue }
            p.state = .inFlight
            inFlightCount += 1
            attempt(id)
        }
    }

    private func attempt(_ id: String) {
        guard let p = pending[id] else {
            inFlightCount = max(0, inFlightCount - 1)
            unsafeSend { _ in self.pump() }
            return
        }

        let record = p.record

        HTTPSessionManager.shared.beNew(priority: .high, self) { session in
            session.beRequest(url: record.url,
                              httpMethod: record.httpMethod,
                              params: record.params,
                              headers: record.headers,
                              cookies: nil,
                              timeoutRetry: self.perAttemptTimeoutRetry,
                              proxy: record.proxy,
                              body: record.body,
                              self) { data, response, error in
                self.complete(id: id, data: data, response: response, error: error)
            }
        }
    }

    private func complete(id: String,
                          data: Data?,
                          response: HTTPURLResponse?,
                          error: String?) {
        inFlightCount = max(0, inFlightCount - 1)

        guard let p = pending[id] else {
            pump()
            return
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
            pending[id] = nil
            removeFile(for: id)
            p.returnCallback?(data, response, error)
            pump()
            return
        }
        
        p.attempts += 1
        
        if isExpired(p.record) {
            pending[id] = nil
            removeFile(for: id)
            p.returnCallback?(nil, response, error)
            pump()
            return
        }
        
        p.state = .waiting
        let delay = backoff(forAttempt: p.attempts)
        scheduleRetry(id: id, delay: delay)
        pump()
    }

    private func scheduleRetry(id: String, delay: TimeInterval) {
        Flynn.Timer(timeInterval: delay, immediate: false, repeats: false, self) { [weak self] _ in
            guard let self = self else { return }
            guard let p = self.pending[id], p.state == .waiting else { return }
            p.state = .ready
            self.readyQueue.append(id)
            self.pump()
        }
    }

    // Exponential backoff with full jitter, capped at maxRetryInterval.
    private func backoff(forAttempt attempt: Int) -> TimeInterval {
        let exponent = Double(min(max(attempt - 1, 0), 16))
        let capped = min(maxRetryInterval, baseRetryInterval * pow(2.0, exponent))
        let low = capped * 0.5
        guard capped > low else { return capped }
        return Double.random(in: low...capped)
    }

    private func isExpired(_ record: DeliveryRecord) -> Bool {
        return Date().timeIntervalSince(record.createdAt) > maxAge
    }

    private func fileURL(for id: String) -> URL {
        return storageURL.appendingPathComponent("\(id).delivery.data", isDirectory: false)
    }

    private func persist(_ record: DeliveryRecord) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(record)
            try data.write(to: fileURL(for: record.id), options: .atomic)
            return nil
        } catch {
            return "failed to persist delivery \(record.id): \(error)"
        }
    }

    private func removeFile(for id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }
    
    private func loadFromDisk() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: storageURL, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let files = try? fm.contentsOfDirectory(at: storageURL,
                                                       includingPropertiesForKeys: nil) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [Pending] = []
        for file in files where file.lastPathComponent.hasSuffix(".delivery.data") {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(DeliveryRecord.self, from: data) else {
                continue
            }
            if isExpired(record) {
                removeFile(for: record.id)
                continue
            }

            loaded.append(Pending(record: record, state: .ready, attempts: 0, returnCallback: nil))
        }
        
        loaded.sort { $0.record.createdAt < $1.record.createdAt }
        for p in loaded {
            pending[p.record.id] = p
            readyQueue.append(p.record.id)
        }
    }
}
