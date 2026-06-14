import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// HTTPDeliveryManager exists to "guarantee" the eventual delivery of a result to a remote endpoint.

public class HTTPDeliveryManager: Actor {

    private struct DeliveryRecord: Codable {
        let id: String
        let url: String
        let httpMethod: String
        let params: [String: String]
        let headers: [String: String]
        let body: Data?
        let proxy: String?
        let priority: String
        let maxAttempts: Int
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
        let onComplete: ((Data?, HTTPURLResponse?, String?) -> ())?

        init(record: DeliveryRecord,
             state: State,
             attempts: Int,
             onComplete: ((Data?, HTTPURLResponse?, String?) -> ())?) {
            self.record = record
            self.state = state
            self.attempts = attempts
            self.onComplete = onComplete
        }
    }

    private let storageURL: URL
    private let failedURL: URL
    private let baseRetryInterval: TimeInterval = 1.0
    private let maxRetryInterval: TimeInterval = 300.0
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private let perAttemptTimeoutRetry = 3

    private var pending: [String: Pending] = [:]
    private var readyQueue: [String] = []          // FIFO of ids whose state == .ready
    private var inFlightCount = 0
    
    private var encrypt: (Data) -> Data
    private var decrypt: (Data) -> Data

    public init(storagePath: String,
                encrypt: ((Data) -> Data)?,
                decrypt: ((Data) -> Data)?) {
        self.storageURL = URL(fileURLWithPath: storagePath, isDirectory: true)
        self.failedURL = URL(fileURLWithPath: storagePath, isDirectory: true)
            .appendingPathComponent("failed", isDirectory: true)
        
        self.encrypt = encrypt ?? { return $0 }
        self.decrypt = decrypt ?? { return $0 }
        
        super.init()

        loadFromDisk()
        unsafeSend { _ in
            self.pump()
        }
    }
    
    public override init() {
        let storagePath = "/tmp"
        
        self.storageURL = URL(fileURLWithPath: storagePath, isDirectory: true)
        self.failedURL = URL(fileURLWithPath: storagePath, isDirectory: true)
            .appendingPathComponent("failed", isDirectory: true)
        
        self.encrypt = { return $0 }
        self.decrypt = { return $0 }
        
        super.init()

        loadFromDisk()
        unsafeSend { _ in
            self.pump()
        }
    }

    internal func _beDeliver(url: String,
                             httpMethod: String,
                             params: [String: String],
                             headers: [String: String],
                             body: Data?,
                             proxy: String?,
                             priority: HTTPSessionPriority,
                             maxAttempts: Int) {
        enqueue(url: url,
                httpMethod: httpMethod,
                params: params,
                headers: headers,
                body: body,
                proxy: proxy,
                priority: priority,
                maxAttempts: maxAttempts,
                onComplete: nil)
    }

    internal func _beDeliver(url: String,
                             httpMethod: String,
                             params: [String: String],
                             headers: [String: String],
                             body: Data?,
                             proxy: String?,
                             priority: HTTPSessionPriority,
                             maxAttempts: Int,
                             _ onComplete: @escaping (Data?, HTTPURLResponse?, String?) -> ()) {
        enqueue(url: url,
                httpMethod: httpMethod,
                params: params,
                headers: headers,
                body: body,
                proxy: proxy,
                priority: priority,
                maxAttempts: maxAttempts,
                onComplete: onComplete)
    }

    private func enqueue(url: String,
                         httpMethod: String,
                         params: [String: String],
                         headers: [String: String],
                         body: Data?,
                         proxy: String?,
                         priority: HTTPSessionPriority,
                         maxAttempts: Int,
                         onComplete: ((Data?, HTTPURLResponse?, String?) -> ())?) {
        let record = DeliveryRecord(id: UUID().uuidString,
                                    url: url,
                                    httpMethod: httpMethod,
                                    params: params,
                                    headers: headers,
                                    body: body,
                                    proxy: proxy,
                                    priority: priority.persisted,
                                    maxAttempts: max(0, maxAttempts),
                                    createdAt: Date())

        // Persist BEFORE we attempt anything. If we cannot write the record we cannot honor the
        // guarantee, so we surface that to the caller rather than pretending success.
        if let error = persist(record) {
            onComplete?(nil, nil, error)
            return
        }

        let p = Pending(record: record, state: .ready, attempts: 0, onComplete: onComplete)
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
        let priority = HTTPSessionPriority(persisted: record.priority)

        HTTPSessionManager.shared.beNew(priority: priority, self) { session in
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

        if error == nil {
            pending[id] = nil
            removeFile(for: id)
            p.onComplete?(data, response, nil)
            pump()
            return
        }

        p.attempts += 1
        let maxAttempts = p.record.maxAttempts
        
        if isExpired(p.record) {
            pending[id] = nil
            removeFile(for: id)
            p.onComplete?(nil, response, error)
            pump()
            return
        }

        if maxAttempts > 0 && p.attempts >= maxAttempts {
            pending[id] = nil
            removeFile(for: id)
            p.onComplete?(nil, response, error)
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
        return storageURL.appendingPathComponent("\(id).data", isDirectory: false)
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
        for file in files where file.lastPathComponent.hasSuffix(".data") {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(DeliveryRecord.self, from: data) else {
                continue
            }
            if isExpired(record) {
                removeFile(for: record.id)
                continue
            }

            loaded.append(Pending(record: record, state: .ready, attempts: 0, onComplete: nil))
        }
        
        loaded.sort { $0.record.createdAt < $1.record.createdAt }
        for p in loaded {
            pending[p.record.id] = p
            readyQueue.append(p.record.id)
        }
    }
}

fileprivate extension HTTPSessionPriority {
    var persisted: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    init(persisted: String) {
        switch persisted {
        case "low": self = .low
        case "high": self = .high
        default: self = .medium
        }
    }
}
