import Flynn
import Foundation
import Hitch
import Spanker

public extension HttpRequest {
    var supportsGzip: Bool {
        return acceptEncoding?.contains("gzip") == true
    }
}
