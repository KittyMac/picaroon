import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// URLSession on Linux, specifically, has issues with sockets getting closed. This is reportedly happening
// when there are a lot of concurrent connections, so URLTask actor provides a simple way to redirect all
// your URLSessions needs through one synchronous entity.
//
// To help combat, we also hold a reference to all outstanding tasks

class URLTask: Actor {
    static let shared = URLTask()
    private override init() { }
    
    private var tasks = Set<URLSessionDataTask>()
    
    public static func urlRequest(url: String,
                                  httpMethod: String,
                                  params: [String: String],
                                  headers: [String: String],
                                  body: Data?,
                                  _ sender: Actor,
                                  _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        URLTask.shared.beRequest(url: url,
                                 httpMethod: httpMethod,
                                 params: params,
                                 headers: headers,
                                 body: body,
                                 sender,
                                 returnCallback)
    }
    
    internal func _beResume(request: URLRequest,
                            _ returnCallback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        _beResume(session: URLSession.shared,
                  request: request,
                  returnCallback)
    }
    
    internal func _beResume(session: URLSession,
                            request: URLRequest,
                            _ returnCallback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        let task = session.dataTask(with: request) { data, response, error in
            self.unsafeSend { _ in
                for task in self.tasks where task.response == response {
                    self.tasks.remove(task)
                    break
                }
                returnCallback(data, response, error)
            }
        }
        tasks.insert(task)
        task.resume()
    }
    
    internal func _beRequest(url: String,
                             httpMethod: String,
                             params: [String: String],
                             headers: [String: String],
                             body: Data?,
                             _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        
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
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        
        guard let url = components.url else {
            returnCallback(nil, nil, "failed to get components url")
            return
        }
        
        var request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 30.0)
        
        request.httpMethod = httpMethod
        request.httpBody = body
        request.httpShouldHandleCookies = false
        
        for (header, value) in headers {
            request.addValue(value, forHTTPHeaderField: header)
        }
        
        _beResume(session: URLSession.shared, request: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                returnCallback(nil, nil, "response is not HTTPURLResponse ( \(data): \(response): \(error) )")
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
}
