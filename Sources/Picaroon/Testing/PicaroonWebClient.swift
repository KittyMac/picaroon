import Foundation
import Flynn

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias kWebViewResponse = (Data?, HTTPURLResponse?, String?) -> Void

public enum PicaroonTesting { }

public extension PicaroonTesting {
    class WebView<T:UserSession> {
        // Simple web browser simulator. Used for testing connection persistance with the UserSession manager
        let client = T()
        
        public var javascriptSessionUUID: String? = nil
        public var serverActorSessionUUID: String?
        
        // Set when an ajax response reported a different Session-Id than the one we sent, meaning our
        // session no longer exists on the server. A real page should adopt the new value and reload.
        public var sessionWasReplaced = false
        
        var cookies = [String:String]()
        
        var lastUrl: String?
        
        public init() {
            
        }
            
        private func handleResponse(data: Data?, httpResponse: HTTPURLResponse?, error: String?, isAjax: Bool) {
            guard let data = data else { fatalError() }
            guard let actorSessionUUID = String(data: data, encoding: .utf8) else { fatalError() }
            
            serverActorSessionUUID = actorSessionUUID
            
            guard let httpResponse = httpResponse else { fatalError() }
                                    
            for (key, value) in httpResponse.allHeaderFields {
                guard let key = key as? String else { continue }
                guard let value = value as? String else { continue }
                
                if key == "Set-Cookie" {
                    // like: <cookie-name>=<cookie-value>
                    // like: <cookie-name>=<cookie-value>; Domain=<domain-value>; Secure; HttpOnly
                    guard let cookieEquation = value.split(separator: ";").first else { continue }
                    let cookieParts = cookieEquation.split(separator: "=")
                    guard let cookieKey: Substring = cookieParts[if: 0] else { continue }
                    guard let cookieValue: Substring = cookieParts[if: 1] else { continue }
                    cookies[String(cookieKey)] = String(cookieValue)
                }
                
                // page script can only see response headers of fetch/XHR, never of its own navigation
                if isAjax,
                   key.lowercased() == "session-id",
                   value != javascriptSessionUUID {
                    javascriptSessionUUID = value
                    sessionWasReplaced = true
                }
            }
        }
        
        private func handleHeaders(isAjax: Bool) -> [String: String] {
            var headers: [String: String] = [:]
            // browsers cannot attach custom headers to a navigation, only to fetch/XHR
            if isAjax, let javascriptSessionUUID = javascriptSessionUUID {
                headers["Session-Id"] = javascriptSessionUUID
            }
            if cookies.count > 0 {
                headers["Cookie"] = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            }
            return headers
        }
        
        public func load(url: String, _ callback: kWebViewResponse?) {
            print("load: \(url)")
                        
            HTTPSessionManager.shared.beNew(Flynn.any) { session in
                
                session.beRequest(url: url,
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: self.handleHeaders(isAjax: false),
                                  cookies: nil,
                                  timeoutRetry: nil,
                                  proxy: nil,
                                  body: nil,
                                  self.client) { data, httpResponse, error in
                    
                    if let data = data,
                       let content = String(data: data, encoding: .utf8) {
                        print(content)
                        if content.contains("Session-Id")  {
                            // "execute" the bootstrap: a conditional one only fills an empty slot
                            let sessionUUID = content.suffix(39).prefix(36)
                            if self.javascriptSessionUUID == nil || content.contains("getItem") == false {
                                self.javascriptSessionUUID = String(sessionUUID)
                            }
                        }
                    }
                    
                    self.handleResponse(data: data, httpResponse: httpResponse, error: error, isAjax: false)
                    if let callback = callback {
                        callback(data, httpResponse, error)
                    }
                }
                
            }
            
            
            
            lastUrl = url
        }
        
        public func ajax(payload: String, _ callback: kWebViewResponse?) {
            guard let lastUrl = lastUrl else { fatalError() }
            
            print("ajax: \(payload)")
            HTTPSessionManager.shared.beNew(Flynn.any) { session in
                session.beRequest(url: lastUrl,
                                  httpMethod: "POST",
                                  params: [:],
                                  headers: self.handleHeaders(isAjax: true),
                                  cookies: nil,
                                  timeoutRetry: nil,
                                  proxy: nil,
                                  body: payload.data(using: .utf8),
                                  self.client) { data, httpResponse, error in
                    self.handleResponse(data: data, httpResponse: httpResponse, error: error, isAjax: true)
                    if let callback = callback {
                        callback(data, httpResponse, error)
                    }
                }
            }
        }
        
        public func reload() {
            
        }
        
        public func clearCookies() {
            cookies.removeAll()
        }
        
    }
}


