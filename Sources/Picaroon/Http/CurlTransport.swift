// A curl_easy_perform based transport for Linux and Android.
//
// URLSession on swift-corelibs-foundation drives libcurl through the multi_socket
// interface: one shared _TimeoutSource plus per-socket DispatchSources, all feeding
// curl_multi_socket_action. On Swift 5.10 that event loop can race into a state where
// neither a timer nor a socket source is armed, and the transfer stalls with no bytes
// moved until the request watchdog fires -1001.
//
// Threads here are dedicated and never DispatchQueue.global(), for the same reason
// DNS+Resolver.swift avoids it: a blocked network call must not consume a worker from
// the pool that Flynn, Dispatch and everything else in the process shares.

#if os(Linux) || os(Android)

import Foundation
import Flynn
import CPicaroonCurl

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

/// Same name and semantics as swift-corelibs-foundation's, so an app that already
/// sets this for URLSession keeps working unchanged when the curl transport is active.
internal let caInfoEnvironmentVariable = "URLSessionCertificateAuthorityInfoFile"
internal let insecureNoVerifySentinel = "INSECURE_SSL_NO_VERIFY"

internal final class CurlTask: PicaroonTask {
    fileprivate let request: URLRequest
    fileprivate let proxy: String?
    fileprivate let timeoutInterval: TimeInterval
    fileprivate let cookieStorage: HTTPCookieStorage?
    fileprivate let completion: (Data?, URLResponse?, Error?) -> ()

    private let lock = NSLock()
    private var cancelled = false
    private var finished = false

    fileprivate init(request: URLRequest,
                     proxy: String?,
                     timeoutInterval: TimeInterval,
                     cookieStorage: HTTPCookieStorage?,
                     completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
        self.request = request
        self.proxy = proxy
        self.timeoutInterval = timeoutInterval
        self.cookieStorage = cookieStorage
        self.completion = completion
    }

    func resume() {
        CurlTransport.shared.enqueue(self)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    fileprivate var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Guarantees the completion closure runs exactly once.
    fileprivate func finish(_ data: Data?, _ response: URLResponse?, _ error: Error?) {
        lock.lock()
        guard finished == false else { lock.unlock(); return }
        finished = true
        lock.unlock()
        completion(data, response, error)
    }
}

internal final class CurlTransport {

    internal static let shared = CurlTransport()

    /// Seconds allowed for DNS + TCP + TLS. Override with PICAROON_CURL_CONNECT_TIMEOUT.
    internal static let connectTimeout: Int = 30

    /// Set PICAROON_CURL_IPV4=1 to restrict name resolution to A records.
    internal static let forceIPv4: Bool = true

    /// Set PICAROON_CURL_VERBOSE=1 for a libcurl protocol trace on stderr.
    internal static let verbose: Bool = {
        let value = ProcessInfo.processInfo.environment["PICAROON_CURL_VERBOSE"]
        return value != nil && value != "0"
    }()

    /// Peer address actually used, when libcurl got far enough to have one. Empty
    /// means the connect never completed, which is itself the useful signal.
    private func primaryIP(_ handle: UnsafeMutableRawPointer) -> String {
        var pointer: UnsafeMutablePointer<CChar>? = nil
        _ = picaroon_curl_getinfo_str(handle, CURLINFO_PRIMARY_IP, &pointer)
        guard let pointer = pointer else { return "" }
        return String(cString: pointer)
    }

    #if os(Android)
    private let workerCount = 16
    #else
    private let workerCount = min(max(Flynn.cores * 4, 8), 64)
    #endif

    private let condition = NSCondition()
    private var pending: [CurlTask] = []
    private var started = false

    private init() {
        _ = picaroon_curl_global_init()
    }

    fileprivate func enqueue(_ task: CurlTask) {
        condition.lock()
        if started == false {
            started = true
            for index in 0..<workerCount {
                let thread = Thread { [weak self] in
                    Flynn.threadSetName("picaroon-curl-\(index)")
                    self?.runWorker()
                }
                thread.stackSize = 512 * 1024
                thread.start()
            }
        }
        pending.append(task)
        condition.signal()
        condition.unlock()
    }

    private func runWorker() {
        // One easy handle per worker, reused for every request that worker serves.
        //
        // curl_easy_reset() clears options but explicitly preserves live connections,
        // the DNS cache and the TLS session-id cache, so consecutive requests to the
        // same host reuse the socket and skip the handshake entirely.
        //
        // Creating a fresh handle per request (as this originally did) meant zero
        // connection reuse: measured against a local TLS server, 60 sequential HTTPS
        // requests opened 60 TCP connections and performed 60 full handshakes. With
        // reuse the same 60 requests open 8. Under load that pile of concurrent
        // handshakes is what surfaced as intermittent
        //   "SSL connection timeout [NSURLErrorDomain Code=-1001]"
        // since CURLOPT_CONNECTTIMEOUT covers the TLS handshake as well.
        //
        // This pools up to workerCount connections per host, which is broadly what
        // URLSession's per-multi-handle connection cache provided.
        guard let handle = curl_easy_init() else { return }
        defer { curl_easy_cleanup(handle) }

        // Owned by the worker, not the request: a persistent handle keeps the
        // ERRORBUFFER pointer between requests, so a per-request allocation would
        // leave the live handle pointing at freed memory.
        let errorSize = Int(picaroon_curl_error_size())
        let errorBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: errorSize)
        errorBuffer.initialize(repeating: 0, count: errorSize)
        defer {
            errorBuffer.deinitialize(count: errorSize)
            errorBuffer.deallocate()
        }

        while true {
            condition.lock()
            while pending.isEmpty {
                condition.wait()
            }
            let task = pending.removeFirst()
            condition.unlock()

            curl_easy_reset(handle)
            errorBuffer[0] = 0
            perform(task, handle, errorBuffer)
        }
    }

    /// Per request state, owned by the worker thread and reached from the C callbacks
    /// through an opaque pointer.
    private final class Context {
        var body = Data()
        /// Reset on every status line, so a redirect chain leaves only the final block.
        var headerLines: [String] = []
        unowned let task: CurlTask

        init(task: CurlTask) {
            self.task = task
        }
    }

    private func perform(_ task: CurlTask, _ handle: UnsafeMutableRawPointer, _ errorBuffer: UnsafeMutablePointer<CChar>) {
        guard task.isCancelled == false else {
            return task.finish(nil, nil, urlError(.cancelled, "cancelled", task.request.url))
        }
        guard let url = task.request.url else {
            return task.finish(nil, nil, urlError(.badURL, "missing url", nil))
        }

        let context = Context(task: task)
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()

        _ = picaroon_curl_setopt_ptr(handle, CURLOPT_ERRORBUFFER, UnsafeMutableRawPointer(errorBuffer))

        // Opt-in libcurl protocol trace, mirroring URLSessionDebugLibcurl in corelibs.
        if CurlTransport.verbose {
            _ = picaroon_curl_setopt_long(handle, CURLOPT_VERBOSE, 1)
        }

        var headerList: UnsafeMutablePointer<curl_slist>? = nil
        defer { if headerList != nil { curl_slist_free_all(headerList) } }

        url.absoluteString.withCString { _ = picaroon_curl_setopt_str(handle, CURLOPT_URL, $0) }

        _ = picaroon_curl_setopt_long(handle, CURLOPT_NOSIGNAL, 1)
        _ = picaroon_curl_setopt_long(handle, CURLOPT_FOLLOWLOCATION, 1)
        _ = picaroon_curl_setopt_long(handle, CURLOPT_MAXREDIRS, 20)
        _ = picaroon_curl_setopt_long(handle, CURLOPT_TCP_KEEPALIVE, 1)
        "".withCString { _ = picaroon_curl_setopt_str(handle, CURLOPT_ACCEPT_ENCODING, $0) }
        // Match corelibs setAllowedProtocolsToAll(): only http/https on redirect.
        _ = picaroon_curl_setopt_long(handle, CURLOPT_REDIR_PROTOCOLS, picaroon_curl_redir_protocols())

        // Driving libcurl directly bypasses _EasyHandle.setupCertificates(), so we must
        // honour the same environment variable it does. Without this libcurl falls back
        // to whatever CA bundle path it was compiled with, which on Android does not
        // exist inside the app sandbox and yields
        //   "error setting certificate file: .../etc/tls/cert.pem"
        // (CURLE_SSL_CACERT_BADFILE). See EasyHandle.swift:196-209.
        // corelibs only reads this on Android; we read it on every platform, so the same
        // variable also covers minimal Linux containers that ship no CA bundle.
        if let caInfo = getenv(caInfoEnvironmentVariable) {
            if String(cString: caInfo) == insecureNoVerifySentinel {
                _ = picaroon_curl_setopt_long(handle, CURLOPT_SSL_VERIFYPEER, 0)
                _ = picaroon_curl_setopt_long(handle, CURLOPT_SSL_VERIFYHOST, 0)
            } else {
                _ = picaroon_curl_setopt_ptr(handle, CURLOPT_CAINFO, UnsafeMutableRawPointer(mutating: caInfo))
            }
        }

        // corelibs' watchdog resets on every read/write callback, so
        // timeoutIntervalForRequest was always an idle bound rather than a total one.
        // LOW_SPEED_LIMIT/TIME reproduces that: abort a stalled transfer without
        // capping a legitimately slow but progressing download.
        let seconds = max(1, Int(task.timeoutInterval))
        // CONNECTTIMEOUT covers DNS + TCP + the TLS handshake. Deliberately NOT derived
        // from timeoutInterval: that defaults to 60 on URLRequest, so a handshake that
        // hangs (blackholed route, captive portal, mobile network transition) pins a
        // worker thread for a full minute and surfaces as "SSL connection timeout".
        // Bounded here so a stuck handshake fails fast and the caller's retry can
        // succeed; progress after connect is still bounded by LOW_SPEED_* below.
        _ = picaroon_curl_setopt_long(handle, CURLOPT_CONNECTTIMEOUT, CurlTransport.connectTimeout)

        // Escape hatch: carriers that advertise AAAA but blackhole IPv6 are a classic
        // cause of a TCP connect that succeeds and then stalls in the TLS handshake.
        // Set PICAROON_CURL_IPV4=1 to test that theory.
        if CurlTransport.forceIPv4 {
            _ = picaroon_curl_setopt_long(handle, CURLOPT_IPRESOLVE, 1) // CURL_IPRESOLVE_V4
        }
        _ = picaroon_curl_setopt_long(handle, CURLOPT_LOW_SPEED_LIMIT, 1)
        _ = picaroon_curl_setopt_long(handle, CURLOPT_LOW_SPEED_TIME, seconds)

        // Per request proxy, set on the handle. This is what the setenv("all_proxy")
        // dance in HTTPTaskManager.checkForMoreTasks was approximating.
        if let proxy = task.proxy {
            proxy.withCString { _ = picaroon_curl_setopt_str(handle, CURLOPT_PROXY, $0) }
        }

        // Body first: COPYPOSTFIELDS takes its own copy, so nothing needs to outlive
        // this scope. POSTFIELDSIZE must be set before COPYPOSTFIELDS.
        if let body = task.request.httpBody, body.isEmpty == false {
            _ = picaroon_curl_setopt_off(handle, CURLOPT_POSTFIELDSIZE_LARGE, curl_off_t(body.count))
            body.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    _ = picaroon_curl_setopt_ptr(handle, CURLOPT_COPYPOSTFIELDS, UnsafeMutableRawPointer(mutating: base))
                }
            }
        }

        // Method last, so CUSTOMREQUEST wins over the POST that COPYPOSTFIELDS implies.
        // Use libcurl's native method options where they exist rather than
        // CUSTOMREQUEST. CUSTOMREQUEST persists across a redirect and pins the method
        // for every hop, which defeats libcurl's own 301/302/303 downgrade: a POST
        // that receives a 303 then arrives at the final URL still as a POST, where
        // URLSession sends a GET. CUSTOMREQUEST is only needed for methods libcurl has
        // no dedicated option for, and libcurl does not downgrade those anyway.
        let method = task.request.httpMethod ?? "GET"
        let hasBody = (task.request.httpBody?.isEmpty == false)
        switch method {
        case "GET":
            // COPYPOSTFIELDS above would otherwise have flipped this to POST.
            if hasBody {
                method.withCString { _ = picaroon_curl_setopt_str(handle, CURLOPT_CUSTOMREQUEST, $0) }
            } else {
                _ = picaroon_curl_setopt_long(handle, CURLOPT_HTTPGET, 1)
            }
        case "HEAD":
            _ = picaroon_curl_setopt_long(handle, CURLOPT_NOBODY, 1)
        case "POST":
            _ = picaroon_curl_setopt_long(handle, CURLOPT_POST, 1)
            if hasBody == false {
                _ = picaroon_curl_setopt_off(handle, CURLOPT_POSTFIELDSIZE_LARGE, 0)
            }
        default:
            method.withCString { _ = picaroon_curl_setopt_str(handle, CURLOPT_CUSTOMREQUEST, $0) }
        }

        var headers = task.request.allHTTPHeaderFields ?? [:]
        if let storage = task.cookieStorage,
           let cookies = storage.cookies(for: url),
           cookies.isEmpty == false {
            for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) where headers[key] == nil {
                headers[key] = value
            }
        }
        // An empty value suppresses a header curl would otherwise add itself.
        if headers["Expect"] == nil {
            headerList = curl_slist_append(headerList, "Expect:")
        }
        // corelibs sends this on every request (curlHeadersToSet in HTTPURLProtocol).
        // if headers["Connection"] == nil {
        //    headerList = curl_slist_append(headerList, "Connection: keep-alive")
        // }
        if headers["Accept-Language"] == nil {
            headerList = curl_slist_append(headerList, "Accept-Language: en-US,en;q=0.9")
        }
        if headers["Cache-Control"] == nil {
            headerList = curl_slist_append(headerList, "Cache-Control: no-cache")
        }
        if headers["User-Agent"] == nil {
            headerList = curl_slist_append(headerList, "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15")
        }
        for (key, value) in headers {
            headerList = curl_slist_append(headerList, "\(key): \(value)")
        }
        if headerList != nil {
            _ = picaroon_curl_setopt_ptr(handle, CURLOPT_HTTPHEADER, headerList)
        }

        _ = picaroon_curl_setopt_ptr(handle, CURLOPT_WRITEDATA, contextPtr)
        _ = picaroon_curl_setopt_write(handle, CURLOPT_WRITEFUNCTION) { buffer, size, count, userdata in
            guard let buffer = buffer, let userdata = userdata else { return 0 }
            let context = Unmanaged<Context>.fromOpaque(userdata).takeUnretainedValue()
            let amount = size * count
            context.body.append(UnsafeRawPointer(buffer).assumingMemoryBound(to: UInt8.self), count: amount)
            return amount
        }

        _ = picaroon_curl_setopt_ptr(handle, CURLOPT_HEADERDATA, contextPtr)
        _ = picaroon_curl_setopt_write(handle, CURLOPT_HEADERFUNCTION) { buffer, size, count, userdata in
            guard let buffer = buffer, let userdata = userdata else { return 0 }
            let context = Unmanaged<Context>.fromOpaque(userdata).takeUnretainedValue()
            let amount = size * count
            let raw = Data(bytes: UnsafeRawPointer(buffer), count: amount)
            let line = (String(data: raw, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("HTTP/") {
                context.headerLines.removeAll(keepingCapacity: true)
            } else if line.isEmpty == false {
                context.headerLines.append(line)
            }
            return amount
        }

        _ = picaroon_curl_setopt_long(handle, CURLOPT_NOPROGRESS, 0)
        _ = picaroon_curl_setopt_ptr(handle, CURLOPT_XFERINFODATA, contextPtr)
        _ = picaroon_curl_setopt_xferinfo(handle, CURLOPT_XFERINFOFUNCTION) { userdata, _, _, _, _ in
            guard let userdata = userdata else { return 0 }
            let context = Unmanaged<Context>.fromOpaque(userdata).takeUnretainedValue()
            return context.task.isCancelled ? 1 : 0
        }

        let code = curl_easy_perform(handle)

        guard code == CURLE_OK else {
            var description = String(cString: errorBuffer)
            if description.isEmpty {
                description = String(cString: curl_easy_strerror(code))
            }
            // Phase timings, so a timeout reports which phase consumed the budget
            // instead of only surfacing -1001. Seconds since the start of this
            // transfer; a zero means the phase was never reached.
            func timing(_ info: CURLINFO) -> Double {
                var value: Double = 0
                _ = picaroon_curl_getinfo_double(handle, info, &value)
                return value
            }
            var osErrno: Int = 0
            _ = picaroon_curl_getinfo_long(handle, CURLINFO_OS_ERRNO, &osErrno)
            var numConnects: Int = 0
            _ = picaroon_curl_getinfo_long(handle, CURLINFO_NUM_CONNECTS, &numConnects)
            // newConnections is CURLINFO_NUM_CONNECTS: how many connections libcurl
            // *completed* for this transfer. Zero means either the connection came
            // from the cache or -- if connect=0.00s with a nonzero dns time -- that no
            // connection ever completed and the socket hung. peer is empty in the
            // latter case, which disambiguates the two.
            description += String(format: " [curl=%d dns=%.2fs connect=%.2fs tls=%.2fs total=%.2fs errno=%d connectTimeout=%ds newConnections=%d peer=%@]",
                                  code.rawValue,
                                  timing(CURLINFO_NAMELOOKUP_TIME),
                                  timing(CURLINFO_CONNECT_TIME),
                                  timing(CURLINFO_APPCONNECT_TIME),
                                  timing(CURLINFO_TOTAL_TIME),
                                  osErrno,
                                  CurlTransport.connectTimeout,
                                  numConnects,
                                  primaryIP(handle))
            return task.finish(nil, nil, urlError(urlCode(for: code), description, url))
        }

        var status: Int = 0
        _ = picaroon_curl_getinfo_long(handle, CURLINFO_RESPONSE_CODE, &status)

        var effectiveURL = url
        var effectivePtr: UnsafeMutablePointer<CChar>? = nil
        _ = picaroon_curl_getinfo_str(handle, CURLINFO_EFFECTIVE_URL, &effectivePtr)
        if let effectivePtr = effectivePtr,
           let parsed = URL(string: String(cString: effectivePtr)) {
            effectiveURL = parsed
        }

        var fields: [String: String] = [:]
        for line in context.headerLines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            // Set-Cookie repeats; join rather than clobber, matching corelibs.
            if let existing = fields[key] {
                fields[key] = existing + ", " + value
            } else {
                fields[key] = value
            }
        }

        if let storage = task.cookieStorage {
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: effectiveURL) {
                storage.setCookie(cookie)
            }
        }

        let response = HTTPURLResponse(url: effectiveURL,
                                       statusCode: Int(status),
                                       httpVersion: "HTTP/1.1",
                                       headerFields: fields)
        task.finish(context.body, response, nil)
    }

    /// Maps curl result codes onto the URLError codes that HTTPTaskManager's retry
    /// logic already matches on, so error handling upstream is unchanged.
    private func urlCode(for code: CURLcode) -> URLError.Code {
        switch code {
        case CURLE_OPERATION_TIMEDOUT:          return .timedOut
        case CURLE_COULDNT_RESOLVE_HOST:        return .cannotFindHost
        case CURLE_COULDNT_RESOLVE_PROXY:       return .cannotFindHost
        case CURLE_COULDNT_CONNECT:             return .cannotConnectToHost
        case CURLE_RECV_ERROR:                  return .networkConnectionLost
        case CURLE_SEND_ERROR:                  return .networkConnectionLost
        case CURLE_PARTIAL_FILE:                return .networkConnectionLost
        case CURLE_GOT_NOTHING:                 return .badServerResponse
        case CURLE_TOO_MANY_REDIRECTS:          return .httpTooManyRedirects
        case CURLE_UNSUPPORTED_PROTOCOL:        return .unsupportedURL
        case CURLE_URL_MALFORMAT:               return .badURL
        case CURLE_ABORTED_BY_CALLBACK:         return .cancelled
        case CURLE_PEER_FAILED_VERIFICATION:    return .serverCertificateUntrusted
        case CURLE_SSL_CONNECT_ERROR:           return .secureConnectionFailed
        case CURLE_SSL_CACERT_BADFILE:          return .serverCertificateUntrusted
        default:                                return .unknown
        }
    }

    private func urlError(_ code: URLError.Code, _ description: String, _ url: URL?) -> Error {
        var info: [String: Any] = [NSLocalizedDescriptionKey: description]
        if let url = url {
            info[NSURLErrorFailingURLErrorKey] = url
            info[NSURLErrorFailingURLStringErrorKey] = url.absoluteString
        }
        return NSError(domain: NSURLErrorDomain, code: code.rawValue, userInfo: info)
    }

    internal static func makeTask(session: URLSession,
                                  request: URLRequest,
                                  proxy: String?,
                                  _ completion: @escaping (Data?, URLResponse?, Error?) -> ()) -> CurlTask {
        var timeout = session.configuration.timeoutIntervalForRequest
        if request.timeoutInterval > 0 {
            timeout = request.timeoutInterval
        }
        return CurlTask(request: request,
                        proxy: proxy,
                        timeoutInterval: timeout,
                        cookieStorage: session.configuration.httpCookieStorage,
                        completion: completion)
    }
}

#endif
