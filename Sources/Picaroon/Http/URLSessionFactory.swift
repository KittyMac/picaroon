import Foundation
import Flynn

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// One place to build a URLSession.
//
// This exists because a URLSession is not always salvageable. On a link which
// drops and comes back - satellite, a carrier NAT rebinding, a handset roaming -
// the far end of a keepalive connection can disappear without ever sending a
// FIN. The socket still looks alive locally, so libcurl keeps it in its
// connection cache, writes the next request into it, and waits out the full
// request timeout. The request after that does the same thing. Nothing in
// URLSession recovers from this by itself.
//
// The only cure is to throw the URLSession away and build another, which means
// the configuration cannot live inline in an initializer that runs once.

internal enum URLSessionFactory {

    internal enum Kind {
        /// Pooled by HTTPSessionManager, one per concurrent caller, cookies on.
        case pooled
        /// Shared, ephemeral, cookies off.
        case oneshot
        /// Shared, ephemeral, cookies off, long request timeout.
        case longshot

        internal var timeoutIntervalForRequest: TimeInterval {
            switch self {
            case .pooled: return 20.0
            case .oneshot: return 20.0
            case .longshot: return 120.0
            }
        }

        internal var allowsCookies: Bool {
            switch self {
            case .pooled: return true
            case .oneshot, .longshot: return false
            }
        }
    }

    internal static func make(_ kind: Kind) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = kind.timeoutIntervalForRequest
        config.timeoutIntervalForResource = 600.0
        config.httpMaximumConnectionsPerHost = HTTPSessionTuning.maximumConnectionsPerHost
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        config.httpShouldUsePipelining = false

        if kind.allowsCookies {
            config.httpCookieAcceptPolicy = .always
        } else {
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil
        }

        return URLSession(configuration: config,
                          delegate: nil,
                          delegateQueue: nil)
    }
}
