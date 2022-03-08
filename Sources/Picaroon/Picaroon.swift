import Foundation
import Flynn
import Hitch

extension String {
    private func substring(with nsrange: NSRange) -> Substring? {
        guard let range = Range(nsrange, in: self) else { return nil }
        return self[range]
    }
    
    func matches(_ pattern: String, _ callback: @escaping ((NSTextCheckingResult, [String]) -> Void)) {
        do {
            let body = self
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsrange = NSRange(location: Int(0), length: Int(count))
            regex.enumerateMatches(in: body, options: [], range: nsrange) { (match, _, _) in
                guard let match = match else { return }
                
                var groups: [String] = []
                for iii in 0..<match.numberOfRanges {
                    if let groupString = body.substring(with: match.range(at: iii)) {
                        groups.append(String(groupString))
                    }
                }
                callback(match, groups)
            }
        } catch { }
    }
}

public enum Picaroon {
    static let userSessionCookie: Hitch = UUID().uuidHitch
    
    public static func urlRequest(url: String,
                                  httpMethod: String,
                                  params: [String: String],
                                  headers: [String: String],
                                  body: Data?,
                                  _ sender: Actor,
                                  _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        
        guard var components = URLComponents(string: url) else {
            sender.unsafeSend {
                returnCallback(nil, nil, "failed to create url components")
            }
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
            sender.unsafeSend {
                returnCallback(nil, nil, "failed to get components url")
            }
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
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let response = response as? HTTPURLResponse else {
                sender.unsafeSend {
                    returnCallback(nil, nil, "response is not an http url response")
                }
                return
            }
            guard let data = data else {
                sender.unsafeSend {
                    returnCallback(nil, response, "response data is nil")
                }
                return
            }
            guard error == nil else {
                sender.unsafeSend {
                    returnCallback(nil, response, "\(error!)")
                }
                return
            }
            
            if response.statusCode >= 200 && response.statusCode <= 299 {
                sender.unsafeSend {
                    returnCallback(data, response, nil)
                }
            } else {
                sender.unsafeSend {
                    returnCallback(data, response, "http \(response.statusCode)")
                }
            }
        }
        task.resume()
        
    }
}
