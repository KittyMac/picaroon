import XCTest
@testable import PicaroonFramework

typealias kWebViewResponse = (Data?, HTTPURLResponse?, String?) -> Void

class WebView {
    // Simple web browser simulator. Used for testing connection persistance with the UserSession manager
    let client = UserSession()
    var javascriptSessionUUID: String? = nil
    
    var serverActorSessionUUID: String?
    
    var cookies = [String:String]()
    
    var lastUrl: String?
    
    init() {
        
    }
    
    init(javascriptSessionUUID: String?) {
        self.javascriptSessionUUID = javascriptSessionUUID
    }
    
    private func handleResponse(data: Data?, httpResponse: HTTPURLResponse?, error: String?) {
        guard let data = data else { return XCTFail() }
        guard let actorSessionUUID = String(data: data, encoding: .utf8) else { return XCTFail() }
        
        serverActorSessionUUID = actorSessionUUID
        
        guard let httpResponse = httpResponse else { return XCTFail() }
                        
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
        }
    }
    
    private func handleHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        if let javascriptSessionUUID = javascriptSessionUUID {
            headers["Session-Id"] = javascriptSessionUUID
        }
        if cookies.count > 0 {
            headers["Cookie"] = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        }
        return headers
    }
    
    func load(url: String, _ callback: kWebViewResponse?) {
        
        client.beUrlRequest(url: url,
                            httpMethod: "GET",
                            params: [:],
                            headers: handleHeaders(),
                            body: nil, client) { data, httpResponse, error in
            
            if self.javascriptSessionUUID == nil {
                self.javascriptSessionUUID = UUID().uuidString
            }
            
            self.handleResponse(data: data, httpResponse: httpResponse, error: error)
            if let callback = callback {
                callback(data, httpResponse, error)
            }
        }
        
        lastUrl = url
    }
    
    func ajax(payload: String, _ callback: kWebViewResponse?) {
        guard let lastUrl = lastUrl else { return XCTFail() }
        client.beUrlRequest(url: lastUrl,
                            httpMethod: "POST",
                            params: [:],
                            headers: handleHeaders(),
                            body: payload.data(using: .utf8), client) { data, httpResponse, error in
            self.handleResponse(data: data, httpResponse: httpResponse, error: error)
            if let callback = callback {
                callback(data, httpResponse, error)
            }
        }
    }
    
    func reload() {
        
    }
    
}
