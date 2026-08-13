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

internal enum HTTPSessionTuning {
    /// Maximum simultaneous connections libcurl will open to one host, per URLSession.
    /// Note: on android this used to be 1. That did not reduce the number of sockets
    /// we create, it only serialized them, which spread the same request volume over
    /// more connection setups and teardowns.
    internal static var maximumConnectionsPerHost: Int {
        #if os(Android)
        return 4
        #else
        return min(max(Flynn.cores * 3, 4), 32)
        #endif
    }

    /// How long an idle URLSession is kept by its current owner before being handed
    /// back to the pool. Without this, a caller making three sequential requests to
    /// the same host releases the session after each one, very likely gets a
    /// different session (with a cold connection cache) for the next, and pays a
    /// fresh TCP + TLS handshake -- and a fresh muxnote lifecycle -- every time.
    internal static var idleSessionLinger: TimeInterval {
        #if os(Android)
        return 2.0
        #else
        return 5.0
        #endif
    }

    /// How long a released URLSession sits out before being issued to a new owner.
    /// Gives libdispatch a chance to finish unregistering the previous owner's
    /// sockets before libcurl starts registering new ones on the same handle.
    internal static let sessionSettleInterval: TimeInterval = 0.1
}

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
            waitingURLSessions.append(
                URLSessionFactory.make(.pooled)
            )
        }
        
        super.init()
        
        unsafePriority = 9999
        unsafeMessageBatchSize = 9999
    }
    
    #if os(Windows)
    private let maxConcurrentSessions = 16
    #elseif os(Linux)
    private let maxConcurrentSessions = Flynn.cores <= 4 ? 8 : 128
    #elseif os(Android)
    private let maxConcurrentSessions = 4
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
        
        httpSession.beBegin(urlSession: urlSession) { returnedURLSession, isSuspect in
            self.unsafeSend { _ in
                self.returnToPool(returnedURLSession,
                                  isSuspect: isSuspect)
            }
        }
    }
    
    /// Hand a URLSession back to the pool - or, if its previous owner lost faith
    /// in it, retire it and put a freshly built one in the pool in its place.
    ///
    /// Recycling the same URLSession objects forever means that a session whose
    /// connection cache has gone bad is handed to the next caller with the bad
    /// cache intact, and the next, indefinitely. The pool has to be able to
    /// replace its contents, not just reorder them.
    private func returnToPool(_ urlSession: URLSession,
                              isSuspect: Bool) {
        var pooledSession = urlSession
        
        if isSuspect {
            HTTPTaskManager.shared.beRetire(session: urlSession)
            pooledSession = URLSessionFactory.make(.pooled)
        }
        
        guard HTTPSessionTuning.sessionSettleInterval > 0 else {
            waitingURLSessions.append(pooledSession)
            checkForMoreSessions()
            return
        }
        
        Flynn.Timer(timeInterval: HTTPSessionTuning.sessionSettleInterval,
                    immediate: false,
                    repeats: false,
                    self) { [weak self] _ in
            guard let self = self else { return }
            self.waitingURLSessions.append(pooledSession)
            self.checkForMoreSessions()
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
