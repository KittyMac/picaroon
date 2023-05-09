import Foundation
import Hitch

public extension String {
    func percentEncoded() -> String? {
        return self.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "/", with: "%2F")
    }
}
