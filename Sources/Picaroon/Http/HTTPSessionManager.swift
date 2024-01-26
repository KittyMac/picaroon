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

public class HTTPSessionManager: Actor {
    public static let shared = HTTPSessionManager()
    private override init() {        
        for _ in 0..<maxConcurrentSessions {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20.0
            config.httpMaximumConnectionsPerHost = max(Flynn.cores * 3, 4)
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.httpCookieAcceptPolicy = .always
            config.httpShouldUsePipelining = true
            
            waitingURLSessions.append(
                URLSession(configuration: config)
            )
        }
    }
    
    private let maxConcurrentSessions = max(Flynn.cores * 3, 4)
    
    private var waitingURLSessions: [URLSession] = []
    private var waitingSessions: [HTTPSession] = []
    
    private func checkForMoreSessions() {
        guard waitingSessions.isEmpty == false else { return }
        guard waitingURLSessions.isEmpty == false else { return }
        
        let urlSession = waitingURLSessions.removeFirst()
        let httpSession = waitingSessions.removeFirst()
        
        httpSession.beBegin(urlSession: urlSession) {
            self.waitingURLSessions.append(urlSession)
            self.checkForMoreSessions()
            
            // Rocco: suspect this is not returning on armv7 android
            //urlSession.reset {
            //    self.unsafeSend { _ in
            //        self.waitingURLSessions.append(urlSession)
            //        self.checkForMoreSessions()
            //    }
            //}
        }
    }
    
    internal func _beNew(_ returnCallback: @escaping (HTTPSession) -> ()) {
        waitingSessions.append(HTTPSession(cookies: [],
                                           returnCallback))
        checkForMoreSessions()
    }
    
    internal func _beNew(cookies: [HTTPCookie],
                         _ returnCallback: @escaping (HTTPSession) -> ()) {
        waitingSessions.append(HTTPSession(cookies: cookies,
                                           returnCallback))
        checkForMoreSessions()
    }
    
    internal func _beOneShot(_ returnCallback: @escaping (HTTPSession) -> ()) {
        returnCallback(HTTPSession.oneshot)
    }
}
