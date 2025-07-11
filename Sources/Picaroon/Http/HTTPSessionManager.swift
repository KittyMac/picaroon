import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// HTTPSessionManager exists solely to work around the many issues URLSession has when used in a server-side context.
//
// On linux, we get -1001 errors if we have too many concurrent tasks / sessions
// On apple, each URLSession maintains a SSL cache which is active for 10 minutes no matter what (memory leak)
//
// To help mitigate these issues, we do the following:
// - Implement a max number of URLSessions allowed, reusing the same pool of sessions to avoid the SSL memory leak
// - Implement a max number of outstanding URL tasks allowed (avoid concentention on sockets)

public enum HTTPSessionPriority {
    case low
    case medium
    case high
    
    func increment() -> HTTPSessionPriority {
        switch self {
        case .low: return .medium
        case .medium: return .high
        default: return .high
        }
    }
}

public class HTTPSessionManager: Actor {
    public static let shared = HTTPSessionManager()
    private override init() {
        for _ in 0..<maxConcurrentSessions {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20.0
            config.httpMaximumConnectionsPerHost = min(max(Flynn.cores * 3, 4), 32)
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.httpCookieAcceptPolicy = .always
            config.httpShouldUsePipelining = false

            waitingURLSessions.append(
                URLSession(configuration: config)
            )
        }
        
        super.init()
        
        unsafePriority = 9999
        unsafeMessageBatchSize = 9999
    }
    
    #if os(Windows)
    private let maxConcurrentSessions = 16
    #elseif os(Linux)
    private let maxConcurrentSessions = 128
    #else
    private let maxConcurrentSessions = min(max(Flynn.cores * 4, 4), 64)
    #endif
    
    private var waitingURLSessions: [URLSession] = []
    
    private var waitingSessionsLow: [HTTPSession] = []
    private var waitingSessionsMedium: [HTTPSession] = []
    private var waitingSessionsHigh: [HTTPSession] = []
        
    private func checkForMoreSessions() {
        guard waitingSessionsLow.isEmpty == false ||
                waitingSessionsMedium.isEmpty == false ||
                waitingSessionsHigh.isEmpty == false else { return }
        guard waitingURLSessions.isEmpty == false else { return }
        
        let urlSession = waitingURLSessions.removeFirst()
        var httpSession: HTTPSession? = nil
        
        if waitingSessionsHigh.isEmpty == false {
            httpSession = waitingSessionsHigh.removeFirst()
        } else if waitingSessionsMedium.isEmpty == false {
            httpSession = waitingSessionsMedium.removeFirst()
        } else if waitingSessionsLow.isEmpty == false {
            httpSession = waitingSessionsLow.removeFirst()
        }
        
        guard let httpSession = httpSession else { return }
        
        httpSession.beBegin(urlSession: urlSession) {
            urlSession.reset {
                self.unsafeSend { _ in
                    self.waitingURLSessions.append(urlSession)
                    self.checkForMoreSessions()
                }
            }
        }
    }
    
    internal func _beNew(priority: HTTPSessionPriority = .medium,
                         _ returnCallback: @escaping (HTTPSession) -> ()) {
        switch priority {
        case .low:
            waitingSessionsLow.append(
                HTTPSession(cookies: [], returnCallback)
            )
        case.medium:
            waitingSessionsMedium.append(
                HTTPSession(cookies: [], returnCallback)
            )
        case.high:
            waitingSessionsHigh.append(
                HTTPSession(cookies: [], returnCallback)
            )
        }
        
        checkForMoreSessions()
    }
    
    internal func _beNew(_ returnCallback: @escaping (HTTPSession) -> ()) {
        return _beNew(priority: .medium,
                      returnCallback)
    }
    
    internal func _beNew(priority: HTTPSessionPriority = .medium,
                         cookies: [HTTPCookie],
                         _ returnCallback: @escaping (HTTPSession) -> ()) {
        switch priority {
        case .low:
            waitingSessionsLow.append(
                HTTPSession(cookies: cookies, returnCallback)
            )
        case.medium:
            waitingSessionsMedium.append(
                HTTPSession(cookies: cookies, returnCallback)
            )
        case.high:
            waitingSessionsHigh.append(
                HTTPSession(cookies: cookies, returnCallback)
            )
        }

        checkForMoreSessions()
    }
    
    internal func _beNew(cookies: [HTTPCookie],
                         _ returnCallback: @escaping (HTTPSession) -> ()) {
        return _beNew(priority: .medium,
                      cookies: cookies,
                      returnCallback)
    }
        
    internal func _beOneShot(_ returnCallback: @escaping (HTTPSession) -> ()) {
        returnCallback(HTTPSession.oneshot)
    }
}
