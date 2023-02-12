import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Note: we cannot have too many concurrent URLSession (or we will get "No space left on device")
// https://stackoverflow.com/questions/67318867/error-domain-nsposixerrordomain-code-28-no-space-left-on-device-userinfo-kcf

// Note: On linux, we get "-1001" errors if we have too many concurrent tasks (regardess of the number of sessions)
// Note: On linux, using just URLSession.shared "works" since max connections per host defaults to 6

// Note: WE MUST BE ABLE TO SUPPORT MULTIPLE CONCURRENT URLSESSIONS, as that is the only way we have separated cookie storage
// Note: We also want to support "one shot" url tasks which are ephemeral, have cookies disabled, and can share a single url session

class Weak<T: AnyObject> {
    weak var value : T?
    init (value: T) {
        self.value = value
    }
}

public class HTTPSessionManager: Actor {
    public static let shared = HTTPSessionManager()
    private override init() { }
    
    private let maxConcurrentSessions = 512
    
    private var waitingSessions: [HTTPSession] = []
    private var activeSessions: [Weak<HTTPSession>] = []
    
    private func checkForMoreSessions() {
        activeSessions.removeAll(where: { $0.value == nil} )
        
        print("check sessions: \(waitingSessions.count) waiting, \(activeSessions.count) active")
        guard waitingSessions.isEmpty == false else { return }
        guard activeSessions.count < maxConcurrentSessions else { return }
        
        let httpSession = waitingSessions.removeFirst()
        activeSessions.append(Weak(value: httpSession))
        
        httpSession.beBegin()
    }
    
    internal func _beNew(_ returnCallback: @escaping (HTTPSession) -> ()) {
        waitingSessions.append(HTTPSession(returnCallback))
        checkForMoreSessions()
    }
    
    internal func _beOneShot(_ returnCallback: @escaping (HTTPSession) -> ()) {
        returnCallback(HTTPSession.oneshot)
    }
    
    internal func _beSessionFinished() {
        self.checkForMoreSessions()
    }
}
