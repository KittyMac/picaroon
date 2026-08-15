import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#else
#error("Unknown platform")
#endif

fileprivate struct HTTPTaskError: LocalizedError, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { return message }
    var description: String { return message }
}

/// Wraps a completion closure such that it is invoked exactly once, from any
/// thread, no matter how many (or how few) code paths try to invoke it.
///
/// This is the backstop which guarantees that every caller of beRequest() /
/// beResume() eventually hears back. In particular:
///  - if some future code path forgets to call the callback, the deinit below
///    will call it with an error instead of hanging the caller forever
///  - if two code paths race to call it, only the first wins
fileprivate final class OnceCallback {
    private let lock = NSLock()
    private var callback: ((Data?, URLResponse?, Error?) -> ())?

    init(_ callback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        self.callback = callback
    }

    deinit {
        // Nobody ever called us and we are about to disappear; the caller is
        // owed a response, so give them an error rather than silence.
        call(nil, nil, HTTPTaskError("http task callback was released before it was ever called"))
    }

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return callback == nil
    }

    @discardableResult
    func call(_ data: Data?, _ response: URLResponse?, _ error: Error?) -> Bool {
        lock.lock()
        let callback = self.callback
        self.callback = nil
        lock.unlock()

        guard let callback = callback else { return false }
        callback(data, response, error)
        return true
    }
}

fileprivate final class DataTask {
    let uuid: String
    let task: URLSessionDataTask
    let proxy: String?

    let deadline: TimeInterval
    let once: OnceCallback

    init(uuid: String,
         task: URLSessionDataTask,
         proxy: String?,
         deadline: TimeInterval,
         once: OnceCallback) {
        self.uuid = uuid
        self.task = task
        self.proxy = proxy
        self.deadline = deadline
        self.once = once
    }
}

internal class HTTPTaskManager: Actor {
    internal static let shared = HTTPTaskManager()
    private override init() {
        super.init()

        unsafePriority = 9999
        unsafeMessageBatchSize = 9999

        Flynn.Timer(timeInterval: 1.0, immediate: false, repeats: true, self) { [weak self] _ in
            guard let self = self else { return }
            self.reapExpiredTasks()
            self.checkForMoreTasks()
        }
    }

    #if os(Windows)
    private let maxConcurrentTasks = 16
    #elseif os(Linux)
    private let maxConcurrentTasks = Flynn.cores <= 4 ? 8 : 512
    #elseif os(Android)
    private let maxConcurrentTasks = 8
    #else
    private let maxConcurrentTasks = min(max(Flynn.cores * 4, 4), 64)
    #endif

    /// Upper bound on the lifetime of one logical request, retries included.
    /// After this we complete with an error rather than leave a caller hanging.
    private let maxRequestLifetime: TimeInterval = 30 * 60
    private let retryInterval: TimeInterval = 1.0

    private var waitingTasks: [DataTask] = []
    private var activeTasks: [DataTask] = []

    private var didWarnAbountProxy = false

    private func now() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    private func checkForMoreTasks() {
        while activeTasks.count < maxConcurrentTasks,
              waitingTasks.isEmpty == false {
            let dataTask = waitingTasks.removeFirst()

            guard dataTask.once.isFinished == false else { continue }

            activeTasks.append(dataTask)
            resume(dataTask: dataTask)
        }
    }

    private func resume(dataTask: DataTask) {
        #if os(Windows)
        dataTask.task.resume()
        #else
        // This is super hacky, but here it goes.
        // We can get per-session-task proxy by setting an environment
        // variable which libcurl uses to know that this requst should
        // be proxied. This var is read in the future on a dispatch
        // queue which URLSessionTask uses internally. We need to
        // set the var, tell the task to resume, and then call
        // some other method on the task which we know sync's to
        // the work queue. Once we return from that, we can clear
        // the proxy var.
        // Note: this is also only safe in the context of Picaroon and HttpSessionManager
        // where all URLSessionTasks are funnelled through the HTTPTaskManager actor
        // (thus none of these will execute concurrently)
        // Note: per session proxies are only supported on linux
        if let proxy = dataTask.proxy {
#if !os(Linux)
            if didWarnAbountProxy == false {
                didWarnAbountProxy = true
                Flynn.syslog("TAG", "warning: URLSessionDataTasks do not support proxy on this platform")
            }
#endif
            setenv("all_proxy", proxy, 1)
            dataTask.task.resume()
            dataTask.task.priority = URLSessionTask.defaultPriority
            unsetenv("all_proxy")
        } else {
            dataTask.task.resume()
        }
        #endif
    }

    private func reapExpiredTasks() {
        let currentTime = now()

        let isExpired: (DataTask) -> Bool = { $0.deadline < currentTime }

        guard activeTasks.contains(where: isExpired) ||
              waitingTasks.contains(where: isExpired) else { return }

        let expired = activeTasks.filter(isExpired) + waitingTasks.filter(isExpired)

        activeTasks.removeAll(where: isExpired)
        waitingTasks.removeAll(where: isExpired)

        for dataTask in expired {
            dataTask.task.cancel()
            dataTask.once.call(nil, nil, HTTPTaskError("http task exceeded its maximum lifetime of \(maxRequestLifetime)s"))
        }
    }

    internal func _beResume(session: URLSession,
                            request: URLRequest,
                            proxy: String?,
                            timeoutRetry: Int,
                            retryAnyError: Bool,
                            _ returnCallback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        submit(session: session,
               request: request,
               proxy: proxy,
               timeoutRetry: timeoutRetry,
               retryAnyError: retryAnyError,
               deadline: now() + maxRequestLifetime,
               once: OnceCallback(returnCallback))
    }

    private func submit(session: URLSession,
                        request: URLRequest,
                        proxy: String?,
                        timeoutRetry: Int,
                        retryAnyError: Bool,
                        deadline: TimeInterval,
                        once: OnceCallback) {
        guard once.isFinished == false else { return }

        guard deadline > now() else {
            once.call(nil, nil, HTTPTaskError("http task exceeded its maximum lifetime of \(maxRequestLifetime)s"))
            return
        }

        let taskUUID = UUID().uuidString
        let task = session.dataTask(with: request) { data, response, error in

#if os(Linux) || os(Android)
            _ = signal(SIGPIPE, SIG_IGN)
#endif

            self.unsafeSend { _ in
                self.finish(uuid: taskUUID,
                            session: session,
                            request: request,
                            proxy: proxy,
                            timeoutRetry: timeoutRetry,
                            retryAnyError: retryAnyError,
                            deadline: deadline,
                            once: once,
                            data: data,
                            response: response,
                            error: error)
            }
        }
        
        waitingTasks.append(DataTask(uuid: taskUUID,
                                     task: task,
                                     proxy: proxy,
                                     deadline: deadline,
                                     once: once))
        checkForMoreTasks()
    }

    private func finish(uuid: String,
                        session: URLSession,
                        request: URLRequest,
                        proxy: String?,
                        timeoutRetry: Int,
                        retryAnyError: Bool,
                        deadline: TimeInterval,
                        once: OnceCallback,
                        data: Data?,
                        response: URLResponse?,
                        error: Error?) {
        activeTasks.removeAll { $0.uuid == uuid }
        waitingTasks.removeAll { $0.uuid == uuid }
        defer { checkForMoreTasks() }

        guard once.isFinished == false else { return }

        var shouldBeRetried: String? = nil

        // Allow specific error to be retried
        if let error = error as? URLError,
           (error.code == .timedOut ||
            error.code == .networkConnectionLost ||
            error.errorCode == 104 ||
            error.errorCode == -1001 ||
            error.errorCode == -1003 ||
            error.errorCode == -1005) {
            shouldBeRetried = "timeout detected \(timeoutRetry), retrying \(request.url?.absoluteString ?? "unknown url")..."
        }

        // If we timeout out, go ahead and retry it.
        #if !os(Windows)
        if let error = error as? POSIXError,
           (error.code == .ENOSPC ||
            error.code == .ECONNRESET ||
            error.errorCode == 54 ||
            error.errorCode == 104 ||
            error.errorCode == -1001 ||
            error.errorCode == -1003 ||
            error.errorCode == -1005) {
            shouldBeRetried = "no space detected \(timeoutRetry), retrying \(request.url?.absoluteString ?? "unknown url")..."
        }
        #else
        if let error = error as? POSIXError,
           (error.code == .ENOSPC ||
            error.errorCode == 104 ||
            error.errorCode == -1001 ||
            error.errorCode == -1003 ||
            error.errorCode == -1005) {
            shouldBeRetried = "no space detected \(timeoutRetry), retrying \(request.url?.absoluteString ?? "unknown url")..."
        }
        #endif

        if error.debugDescription.contains("hostname could not be found") {
            shouldBeRetried = nil
        }

        if retryAnyError {
            // Any transport error
            if let error = error {
                shouldBeRetried = "retry any error: \(error)"
            }
            // Any non-success HTTP error
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                shouldBeRetried = "retry any error: http \(httpResponse.statusCode)"
            }
        }

        // Retries on specific error string content
        if let errorString = error?.localizedDescription,
           timeoutRetry > 0 {
            let retryErrorStrings = [
                "Transferred a partial file"
            ]

            for retryErrorString in retryErrorStrings where errorString.contains(retryErrorString) {
                shouldBeRetried = "\(retryErrorString) \(timeoutRetry), retrying \(request.url?.absoluteString ?? "unknown url")..."
            }
        }

        guard let shouldBeRetried = shouldBeRetried,
              timeoutRetry > 0,
              deadline > now() + retryInterval else {
            once.call(data, response, error)
            return
        }

        var newRequest = request

        #if os(Android)
        if request.timeoutInterval == 2 {
            newRequest.timeoutInterval = 60
        }
        #endif

        let localNewRequest = newRequest

        Flynn.Timer(timeInterval: self.retryInterval, immediate: false, repeats: false, self) { [weak self] _ in
            guard let self = self else {
                once.call(nil, nil, HTTPTaskError("http task manager went away before retry"))
                return
            }
            self.submit(session: session,
                        request: localNewRequest,
                        proxy: proxy,
                        timeoutRetry: timeoutRetry - 1,
                        retryAnyError: retryAnyError,
                        deadline: deadline,
                        once: once)
        }
    }
}
