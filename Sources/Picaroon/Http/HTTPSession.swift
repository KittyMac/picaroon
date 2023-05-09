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
    
    private var urlSession: URLSession = URLSession.shared
    private var beginCallback: ((HTTPSession) -> ())?
    private var deinitCallback: (() -> ())?
    private var sessionCookies: HTTPCookieStorage?
    
    internal var safeS3Key: String?
    internal var safeS3Secret: String?
    
    public init(cookies: HTTPCookieStorage?,
                _ returnCallback: @escaping (HTTPSession) -> ()) {
        sessionCookies = cookies
        beginCallback = returnCallback
    }
    
    fileprivate init(oneshot: Bool) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10.0
        config.httpMaximumConnectionsPerHost = max(Flynn.cores * 3, 4)
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpShouldUsePipelining = true
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }
    
    deinit {
        guard let deinitCallback = deinitCallback else { return }
        HTTPSessionManager.shared.unsafeSend { _ in
            deinitCallback()
        }
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
                if let sessionCookies = self.sessionCookies?.cookies {
                    for cookie in sessionCookies {
                        httpCookieStorage.setCookie(cookie)
                    }
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
                             proxy: String?,
                             _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> ()) {
        HTTPTaskManager.shared.beResume(session: urlSession,
                                        request: request,
                                        proxy: proxy,
                                        timeoutRetry: 3,
                                        self) { data, response, error in
            self.handleTaskResponse(data: data,
                                    response: response,
                                    error: error,
                                    returnCallback: returnCallback)
        }
    }
    
    internal func _beRequest(url: String,
                             httpMethod: String,
                             params: [String: String],
                             headers: [String: String],
                             cookies: HTTPCookieStorage? = nil,
                             proxy: String?,
                             body: Data?,
                             _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        guard urlSession != URLSession.shared else { fatalError("HTTPSession is not allowed to use URLSession.shared") }
        
        guard var components = URLComponents(string: url) else {
            returnCallback(nil, nil, "failed to create url components")
            return
        }
        
        if components.queryItems == nil {
            components.queryItems = []
        }
        
        params.forEach { (key, value) in
            components.queryItems?.append(URLQueryItem(name: key, value: value))
        }
        components.percentEncodedQuery = components.query?.percentEncoded()
        
        guard let url = components.url else {
            returnCallback(nil, nil, "failed to get components url")
            return
        }
        
        var request = URLRequest(url: url)
        
        request.httpMethod = httpMethod
        request.httpBody = body
        
        for (header, value) in headers {
            request.addValue(value, forHTTPHeaderField: header)
        }
        
        if let cookies = cookies?.cookies {
            for (header, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.addValue(value, forHTTPHeaderField: header)
            }
        }
        
        HTTPTaskManager.shared.beResume(session: urlSession,
                                        request: request,
                                        proxy: proxy,
                                        timeoutRetry: 3,
                                        self) { data, response, error in
            self.handleTaskResponse(data: data,
                                    response: response,
                                    error: error,
                                    returnCallback: returnCallback)
        }
    }
    
    private func handleTaskResponse(data: Data?,
                                    response: URLResponse?,
                                    error: Error?,
                                    returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        if let error = error {
            returnCallback(nil, nil, "\(error.localizedDescription) [\(error)]")
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            let dataDesc = data?.description ?? "nil"
            let responseDesc = response?.description ?? "nil"
            var errorDesc = "nil"
            if let error = error {
                errorDesc = "\(error.localizedDescription) [\(error)]"
            }
            returnCallback(nil, nil, "response is not HTTPURLResponse ( \(dataDesc): \(responseDesc): \(errorDesc) )")
            return
        }
        guard let data = data else {
            returnCallback(nil, httpResponse, "httpResponse data is nil")
            return
        }
        guard error == nil else {
            returnCallback(nil, httpResponse, "\(error!)")
            return
        }
        
        if httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299 {
            returnCallback(data, httpResponse, nil)
        } else {
            returnCallback(data, httpResponse, "http \(httpResponse.statusCode)")
        }
        
    }
}
