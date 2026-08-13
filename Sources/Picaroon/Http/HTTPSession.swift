// flynn:ignore Access Level Violation

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

// Note: we cannot have too many concurrent URLSession (or we will get "No space left on device")
// https://stackoverflow.com/questions/67318867/error-domain-nsposixerrordomain-code-28-no-space-left-on-device-userinfo-kcf

// Note: On linux, we get "-1001" errors if we have too many concurrent connections (regardess of the number of sessions)
// Note: On linux, using just URLSession.shared "works" since max connections per host defaults to 6
// Note: On linux, URLSession does not ignore sigpipe ( https://github.com/apple/swift-corelibs-foundation/issues/4407 )
//       we attempt to combat this by calling _ = signal(SIGPIPE, SIG_IGN) on all threads we have access to

// Note: WE MUST BE ABLE TO SUPPORT MULTIPLE CONCURRENT URLSESSIONS, as that is the only way we have separated cookie storage
// Note: We also want to support "one shot" url tasks which are ephemeral, have cookies disabled, and can share a single url session

public class HTTPSession: Actor {
    public static let oneshot: HTTPSession = HTTPSession(owned: .oneshot)
    public static let longshot: HTTPSession = HTTPSession(owned: .longshot)
    
    /// On android the first network call after launch reliably times out, so we
    /// give it a deliberately small timeout and let the retry do the real work.
    internal static let androidFirstCallTimeout: TimeInterval = 2
    
    /// How many request timeouts in a row against one host before we stop
    /// believing in this URLSession. Two is enough to tell a single dropped
    /// request apart from a connection cache full of dead keepalive sockets.
    private let maxConsecutiveTimeouts = 2
    
    private var urlSession: URLSession = URLSession.shared
    
    /// Non nil when this HTTPSession built its own URLSession and is therefore
    /// entitled to throw it away and build another. Pooled sessions borrow
    /// theirs from HTTPSessionManager and can only flag it as suspect on the
    /// way out.
    private let ownedSessionKind: URLSessionFactory.Kind?
    
    /// Consecutive request timeouts, keyed by host.
    ///
    /// Per host rather than per session because one URLSession can be serving
    /// several hosts at once (HTTPSession.longshot serves all of them), and the
    /// two situations we have to tell apart look identical in aggregate: one host
    /// wedged while the others are fine is a poisoned connection, whereas every
    /// host failing at once is just the link being down.
    private var consecutiveTimeouts: [String: Int] = [:]
    private var sessionIsSuspect = false
    
    private var beginCallback: ((HTTPSession) -> ())?
    private var deinitCallback: ((URLSession, Bool) -> ())?
    private var sessionCookies: [HTTPCookie] = []
    
    internal var safeS3Key: String?
    internal var safeS3Secret: String?
    
    private var outstandingRequests = 0
    
    /// Bumped every time we schedule a deferred release. A release only fires if
    /// it is still the most recently scheduled one, so new work arriving during
    /// the linger window silently cancels the pending release.
    private var idleReleaseGeneration = 0
        
    private var firstTimeCalled = true
    private let retryAnyError: Bool
    
    public init(cookies: [HTTPCookie],
                _ returnCallback: @escaping (HTTPSession) -> ()) {
        sessionCookies = cookies
        beginCallback = returnCallback
        retryAnyError = false
        ownedSessionKind = nil
        
        super.init()
        unsafePriority = 9999
        unsafeMessageBatchSize = 100
    }
    
    fileprivate init(owned kind: URLSessionFactory.Kind) {
        ownedSessionKind = kind
        urlSession = URLSessionFactory.make(kind)
        retryAnyError = (kind == .longshot)
        
        super.init()
        unsafePriority = 9999
        unsafeMessageBatchSize = 100
    }
    
    private func releaseUrlSession() {
        if let deinitCallback = self.deinitCallback {
            self.deinitCallback = nil
            let releasedUrlSession = self.urlSession
            let releasedIsSuspect = self.sessionIsSuspect
            self.sessionIsSuspect = false
            self.urlSession = URLSession.shared
            HTTPSessionManager.shared.unsafeSend { _ in
                deinitCallback(releasedUrlSession, releasedIsSuspect)
            }
        }
    }
    
    /// Whether an error means "we wrote a request into a socket which looked
    /// alive and nothing ever came back".
    ///
    /// Deliberately narrow: this is the only error which indicates a connection
    /// libcurl will happily keep on reusing.
    ///  - a resolve failure (-1003) never got a socket at all, so replacing the
    ///    session cannot possibly help
    ///  - an aborted or reset connection means the kernel already tore the socket
    ///    down, so curl will not reuse it - that recovers on its own
    ///  - our own HTTPTaskError is not a URLError, so cancellations and
    ///    retirements cannot count towards retiring anything else. That part
    ///    matters: counting them meant one recycle cancelled its sibling tasks,
    ///    and those cancellations immediately retired the replacement session.
    private func isRequestTimeout(_ error: Error?) -> Bool {
        guard let error = error else { return false }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut || urlError.errorCode == -1001
        }
        if let posixError = error as? POSIXError {
            return posixError.errorCode == -1001
        }
        return false
    }
    
    /// Called on this actor once per completed request.
    private func noteCompletion(host: String?,
                                response: HTTPURLResponse?,
                                error: Error?) {
        guard let host = host else { return }
        
        // Any HTTPURLResponse at all - 4xx and 5xx included - proves this
        // connection carries traffic, so anything counted against this host is
        // stale.
        guard response == nil else {
            consecutiveTimeouts.removeValue(forKey: host)
            return
        }
        
        // Other transport errors are left uncounted rather than resetting the
        // count: they are evidence of neither a healthy nor a poisoned
        // connection, and a flaky link produces a great many of them.
        guard isRequestTimeout(error) else { return }
        
        let timeouts = (consecutiveTimeouts[host] ?? 0) + 1
        consecutiveTimeouts[host] = timeouts
        
        guard timeouts >= maxConsecutiveTimeouts else { return }
        
        recycleUrlSession(host: host)
    }
    
    private func recycleUrlSession(host: String) {
        // The counts belong to the session we are about to stop using.
        consecutiveTimeouts.removeAll()
        
        guard let ownedSessionKind = ownedSessionKind else {
            // Borrowed from the pool: we cannot swap it out from under the
            // manager, so flag it and let the manager replace it on release.
            sessionIsSuspect = true
            Flynn.syslog("TAG", "warning: flagged a pooled url session as suspect after \(maxConsecutiveTimeouts) consecutive timeouts against \(host)")
            return
        }
        
        let poisoned = urlSession
        guard poisoned !== URLSession.shared else { return }
        
        urlSession = URLSessionFactory.make(ownedSessionKind)
        
        // Retiring happens on the HTTPTaskManager actor so that no already
        // queued task can be resumed on a session which has been invalidated
        // in the meantime - such a task never calls back at all.
        HTTPTaskManager.shared.beRetire(session: poisoned)
        
        Flynn.syslog("TAG", "warning: replaced the \(ownedSessionKind) url session after \(maxConsecutiveTimeouts) consecutive timeouts against \(host)")
    }
    
    /// Hold on to the URLSession for a little while after going idle, rather than
    /// handing it straight back to the pool.
    ///
    /// Releasing immediately looks tidy but is expensive: a caller making several
    /// sequential requests to the same host would release after each one, get a
    /// different session (with a cold connection cache) for the next, and pay a
    /// fresh TCP + TLS handshake every time. Every one of those handshakes is also a
    /// socket registration and unregistration inside libdispatch, which is the churn
    /// that drives the muxnote use-after-free on android.
    private func scheduleReleaseUrlSession() {
        guard deinitCallback != nil else { return }
        
        idleReleaseGeneration += 1
        let generation = idleReleaseGeneration
        
        Flynn.Timer(timeInterval: HTTPSessionTuning.idleSessionLinger,
                    immediate: false,
                    repeats: false,
                    self) { [weak self] _ in
            guard let self = self else { return }
            guard self.idleReleaseGeneration == generation else { return }
            guard self.outstandingRequests == 0 else { return }
            self.releaseUrlSession()
        }
    }
    
    deinit {
        releaseUrlSession()
    }
    
    // Note: we define the behavior this way because we don't want it exposed outside of the module
    internal func beBegin(urlSession: URLSession,
                          _ deinitCallback: @escaping (URLSession, Bool) -> ()) {
        unsafeSend { _ in
            guard let beginCallback = self.beginCallback else { fatalError("cannot call beBegin() on HTTPSession twice") }
            self.beginCallback = nil
            self.urlSession = urlSession
            self.deinitCallback = deinitCallback
            
            #if os(Linux) || os(Android)
            _ = signal(SIGPIPE, SIG_IGN)
            #endif
            
            if let httpCookieStorage = urlSession.configuration.httpCookieStorage {
                httpCookieStorage.removeCookies(since: Date.distantPast)
                for cookie in self.sessionCookies {
                    httpCookieStorage.setCookie(cookie)
                }
            }

            beginCallback(self)
        }
    }
    
    internal func _beCancel() {
        guard self != HTTPSession.oneshot else { fatalError("You cannot cancel the oneshot HTTPSession") }
        
        HTTPTaskManager.shared.beCancelAll(session: urlSession)
        
        // Anything still in flight will come back through the completion path and
        // release the session as it drains. If there is nothing in flight, there is
        // nothing to wait for.
        if outstandingRequests == 0 {
            releaseUrlSession()
        }
    }
        
    internal func _beRequest(request: URLRequest,
                             timeoutRetry: Int?,
                             proxy: String?,
                             _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> ()) {
        let host = request.url?.host
        outstandingRequests += 1
        HTTPTaskManager.shared.beResume(session: urlSession,
                                        request: request,
                                        proxy: proxy,
                                        timeoutRetry: timeoutRetry ?? 3,
                                        retryAnyError: retryAnyError,
                                        self) { data, response, error in
            let (data2, respose2, error2) = handleTaskResponse(data: data,
                                                               response: response,
                                                               error: error)
            returnCallback(data2, respose2, error2)
            
            self.noteCompletion(host: host,
                                response: respose2,
                                error: error)
            
            self.outstandingRequests -= 1
            if self.outstandingRequests == 0 {
                self.scheduleReleaseUrlSession()
            }
        }
    }
    
    internal func _beRequest(url: String,
                             httpMethod: String,
                             params: [String: String],
                             headers: [String: String],
                             cookies: HTTPCookieStorage? = nil,
                             timeoutRetry: Int?,
                             proxy: String?,
                             body: Data?,
                             _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        guard urlSession != URLSession.shared else {
            returnCallback(nil, nil, "HTTPSession is not allowed to use URLSession.shared")
            return
        }
        
        let (request, error) = makeRequest(urlSession: urlSession,
                                           url: url,
                                           httpMethod: httpMethod,
                                           params: params,
                                           headers: headers,
                                           cookies: cookies,
                                           timeoutRetry: timeoutRetry,
                                           proxy: proxy,
                                           body: body)
        
        guard let request = request else {
            returnCallback(nil, nil, error ?? "unknown error")
            return
        }
                
        let host = request.url?.host
        outstandingRequests += 1
        HTTPTaskManager.shared.beResume(session: urlSession,
                                        request: request,
                                        proxy: proxy,
                                        timeoutRetry: timeoutRetry ?? 3,
                                        retryAnyError: retryAnyError,
                                        self) { data, response, error in
            let (data2, respose2, error2) = handleTaskResponse(data: data,
                                                               response: response,
                                                               error: error)
            returnCallback(data2, respose2, error2)
            
            self.noteCompletion(host: host,
                                response: respose2,
                                error: error)
            
            self.outstandingRequests -= 1
            if self.outstandingRequests == 0 {
                self.scheduleReleaseUrlSession()
            }
        }
    }
    
    private func makeRequest(urlSession: URLSession,
                             url: String,
                             httpMethod: String,
                             params: [String: String],
                             headers: [String: String],
                             cookies: HTTPCookieStorage? = nil,
                             timeoutRetry: Int?,
                             proxy: String?,
                             body: Data?) -> (URLRequest?, String?) {
        guard var components = URLComponents(string: url) else {
            return (nil, "failed to create url components")
        }
        
        // At this point components.queryItems contains the queries embedded in the url
        // in an percent unescaped fashion. components.url will, by default, attempt to
        // percent escape the query string. However, the percent escaping it performs does
        // not appear to be standard. Specifically, things like "/" and "+" do not get
        // escaped. Some service (like Amazon S3) require that the queries be properly
        // percent escaped.
        // To work around this, we generate an array of unescaped query items, then we
        // manually percent escape each name and value using a custom percentEncoded method.
        // Finally override components.percentEncodedQuery with components.query which
        // will be the correct string with unescaped &name=value while "name" and "value"
        // are escaped.
        var unescapedQueryItems: [URLQueryItem] = []
        if let originalQueryItems = components.queryItems {
            for originalQueryItem in originalQueryItems {
                unescapedQueryItems.append(originalQueryItem)
            }
        }
        
        params.forEach { (key, value) in
            unescapedQueryItems.append(URLQueryItem(name: key,
                                                    value: value))
        }
        
        if unescapedQueryItems.count > 0 {
            components.queryItems = []
            for unescapedQueryItem in unescapedQueryItems {
                components.queryItems?.append(URLQueryItem(name: unescapedQueryItem.name.percentEncoded() ?? unescapedQueryItem.name,
                                                           value: unescapedQueryItem.value?.percentEncoded() ?? unescapedQueryItem.value))
            }
        }
        
        components.percentEncodedQuery = components.query
        
        
        guard let url = components.url else {
            return(nil, "failed to get components url")
        }
        
        var request = URLRequest(url: url)
        
        request.httpMethod = httpMethod
        request.httpBody = body
        
        #if os(Android)
        // On android specifically, the first time we make a network call it always time outs
        // To help work around this, we give the first network call a small timeout value
        if firstTimeCalled {
            firstTimeCalled = false
            request.timeoutInterval = Self.androidFirstCallTimeout
        }
        #endif
        
        for (header, value) in headers {
            request.addValue(value, forHTTPHeaderField: header)
        }
        
        if let cookies = cookies?.cookies {
            for (header, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.addValue(value, forHTTPHeaderField: header)
            }
        }

        return (request, nil)
    }
    
    
    /// For use only when you need to do a synchronous network conneciton on a Flynn actor.
    /// In such a scenario, using the normal cooperative scheduling system can lead to
    /// a deadlock (all actors on all schedulers holding their thread such that their
    /// dependent actors never get a chance to run). In such a scenario we can instead
    /// use GCD only.
    /// Note: these tasks do not have automatic retries
    public func unsafeSynchronousRequest(url: String,
                                         httpMethod: String,
                                         params: [String: String],
                                         headers: [String: String],
                                         cookies: HTTPCookieStorage? = nil,
                                         timeoutRetry: Int?,
                                         proxy: String?,
                                         body: Data?) -> (Data?, HTTPURLResponse?, String?) {
        // NOTE: it is important not to reference self in this method!
        guard urlSession != URLSession.shared else {
            return (nil, nil, "HTTPSession is not allowed to use URLSession.shared")
        }

        let (request, error) = makeRequest(urlSession: urlSession,
                                           url: url,
                                           httpMethod: httpMethod,
                                           params: params,
                                           headers: headers,
                                           cookies: cookies,
                                           timeoutRetry: timeoutRetry,
                                           proxy: proxy,
                                           body: body)
        
        guard let request = request else {
            return (nil, nil, error ?? "unknown error")
        }

        let group = DispatchGroup()
        group.enter()
        
        var returnData: Data? = nil
        var returnResponse: HTTPURLResponse? = nil
        var returnError: String? = nil
                
        urlSession.dataTask(with: request) { data, response, error in
            (returnData, returnResponse, returnError) = handleTaskResponse(data: data,
                                                                           response: response,
                                                                           error: error)
            group.leave()
        }.resume()
        
        group.wait()
        
        return (returnData, returnResponse, returnError)
    }
    
    public func unsafeAsynchronousRequest(url: String,
                                          httpMethod: String,
                                          params: [String: String],
                                          headers: [String: String],
                                          cookies: HTTPCookieStorage? = nil,
                                          timeoutRetry: Int?,
                                          proxy: String?,
                                          body: Data?,
                                          _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        // NOTE: it is important not to reference self in this method!
        guard urlSession != URLSession.shared else {
            returnCallback(nil, nil, "HTTPSession is not allowed to use URLSession.shared")
            return
        }

        let (request, error) = makeRequest(urlSession: urlSession,
                                           url: url,
                                           httpMethod: httpMethod,
                                           params: params,
                                           headers: headers,
                                           cookies: cookies,
                                           timeoutRetry: timeoutRetry,
                                           proxy: proxy,
                                           body: body)
        
        guard let request = request else {
            returnCallback(nil, nil, error ?? "unknown error")
            return
        }

        urlSession.dataTask(with: request) { data, response, error in
            let (returnData, returnResponse, returnError) = handleTaskResponse(data: data,
                                                                               response: response,
                                                                               error: error)
            returnCallback(returnData, returnResponse, returnError)
        }.resume()
    }
}

fileprivate func handleTaskResponse(data: Data?,
                                    response: URLResponse?,
                                    error: Error?) -> (Data?, HTTPURLResponse?, String?) {
    if let error = error {
        return (nil, nil, "\(error.localizedDescription) [\(error)]")
    }
    guard let httpResponse = response as? HTTPURLResponse else {
        let dataDesc = data?.description ?? "nil"
        let responseDesc = response?.description ?? "nil"
        var errorDesc = "nil"
        if let error = error {
            errorDesc = "\(error.localizedDescription) [\(error)]"
        }
        return (nil, nil, "response is not HTTPURLResponse ( \(dataDesc): \(responseDesc): \(errorDesc) )")
    }
    guard let data = data else {
        return (nil, httpResponse, "httpResponse data is nil")
    }
    guard error == nil else {
        return (nil, httpResponse, "\(error!)")
    }
    
    if httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299 {
        return (data, httpResponse, nil)
    } else {
        return (data, httpResponse, "http \(httpResponse.statusCode)")
    }
}
