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
        
        // Forcing the same operation queue across all url sessions is probably overly aggressive to fix the linue issue
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        
        for _ in 0..<maxConcurrentSessions {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10.0
            config.httpMaximumConnectionsPerHost = 1024
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            waitingURLSessions.append(
                URLSession(configuration: config,
                           delegate: nil,
                           delegateQueue: operationQueue)
            )
        }
    }
    
    private let maxConcurrentSessions = 512
    
    private var waitingURLSessions: [URLSession] = []
    private var waitingSessions: [HTTPSession] = []
    
    private func checkForMoreSessions() {
        guard waitingSessions.isEmpty == false else { return }
        guard waitingURLSessions.isEmpty == false else { return }
        
        let urlSession = waitingURLSessions.removeFirst()
        let httpSession = waitingSessions.removeFirst()
        
        httpSession.beBegin(urlSession: urlSession) {
            urlSession.reset {
                self.waitingURLSessions.append(urlSession)
                self.checkForMoreSessions()
            }
        }
    }
    
    internal func _beNew(_ returnCallback: @escaping (HTTPSession) -> ()) {
        waitingSessions.append(HTTPSession(returnCallback))
        checkForMoreSessions()
    }
    
    internal func _beOneShot(_ returnCallback: @escaping (HTTPSession) -> ()) {
        returnCallback(HTTPSession.oneshot)
    }
}
