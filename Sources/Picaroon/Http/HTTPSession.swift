import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
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
    public static let oneshot: HTTPSession = HTTPSession(oneshot: true)
    public static let longshot: HTTPSession = HTTPSession(longshot: true)
    
    private var urlSession: URLSession = URLSession.shared
    private var beginCallback: ((HTTPSession) -> ())?
    private var deinitCallback: (() -> ())?
    private var sessionCookies: [HTTPCookie] = []
    
    internal var safeS3Key: String?
    internal var safeS3Secret: String?
    
    private var outstandingRequests = 0
    
    private var firstTimeCalled = true
    
    public init(cookies: [HTTPCookie],
                _ returnCallback: @escaping (HTTPSession) -> ()) {
        sessionCookies = cookies
        beginCallback = returnCallback
    }
    
    fileprivate init(oneshot: Bool) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20.0
        config.httpMaximumConnectionsPerHost = min(max(Flynn.cores * 3, 4), 32)
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpShouldUsePipelining = true
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }
    
    fileprivate init(longshot: Bool) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120.0
        config.timeoutIntervalForResource = 120.0
        config.httpMaximumConnectionsPerHost = min(max(Flynn.cores * 3, 4), 32)
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpShouldUsePipelining = true
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }
    
    private func releaseUrlSession() {
        if let deinitCallback = deinitCallback {
            self.deinitCallback = nil
            self.urlSession = URLSession.shared
            HTTPSessionManager.shared.unsafeSend { _ in
                deinitCallback()
            }
        }
    }
    
    deinit {
        releaseUrlSession()
    }
    
    // Note: we define the behavior this way because we don't want it exposed outside of the module
    internal func beBegin(urlSession: URLSession,
                          _ deinitCallback: @escaping () -> ()) {
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
        urlSession.invalidateAndCancel()
        urlSession = URLSession.shared
    }
        
    internal func _beRequest(request: URLRequest,
                             timeoutRetry: Int?,
                             proxy: String?,
                             _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> ()) {
        outstandingRequests += 1
        HTTPTaskManager.shared.beResume(session: urlSession,
                                        request: request,
                                        proxy: proxy,
                                        timeoutRetry: timeoutRetry ?? 3,
                                        self) { data, response, error in
            let (data2, respose2, error2) = handleTaskResponse(data: data,
                                                               response: response,
                                                               error: error)
            returnCallback(data2, respose2, error2)
            
            self.outstandingRequests -= 1
            if self.outstandingRequests == 0 {
                self.releaseUrlSession()
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
                
        outstandingRequests += 1
        HTTPTaskManager.shared.beResume(session: urlSession,
                                        request: request,
                                        proxy: proxy,
                                        timeoutRetry: timeoutRetry ?? 3,
                                        self) { data, response, error in
            let (data2, respose2, error2) = handleTaskResponse(data: data,
                                                               response: response,
                                                               error: error)
            returnCallback(data2, respose2, error2)

            self.outstandingRequests -= 1
            if self.outstandingRequests == 0 {
                self.releaseUrlSession()
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
            request.timeoutInterval = 2
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
