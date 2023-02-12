import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
    public static var userSessionCookie: Hitch = UUID().uuidHitch
    
    public static func urlRequest(url: String,
                                  httpMethod: String,
                                  params: [String: String],
                                  headers: [String: String],
                                  body: Data?,
                                  _ sender: Actor,
                                  _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        // Note: this functionality has been moved to URLTask
        URLTask.shared.beRequest(url: url,
                                 httpMethod: httpMethod,
                                 params: params,
                                 headers: headers,
                                 body: body,
                                 sender,
                                 returnCallback)
    }
}
