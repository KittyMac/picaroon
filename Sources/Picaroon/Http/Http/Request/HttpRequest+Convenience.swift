import Flynn
import Foundation
import Hitch
import Spanker

public extension HttpRequest {
    var supportsGzip: Bool {
        #if DEBUG
        return false
        #else
        return acceptEncoding?.contains("gzip") == true
        #endif
    }
}
