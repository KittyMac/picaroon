import Flynn
import Foundation
import Socket

public typealias GetUserSessionCallback = (UserSession?) -> Void

protocol AnyUserSessionManager {
    func get(_ sessionUUID: String?) -> UserSession
    func end(_ sessionUUID: String)
}

public class UserSessionManager<T: UserSession>: AnyUserSessionManager {

    private var allUserSessions: [String: UserSession] = [:]
    private var lock = NSLock()

    func get(_ sessionUUID: String?) -> UserSession {
        lock.lock()
        defer {
            lock.unlock()
        }

        if let sessionUUID = sessionUUID, sessionUUID.count > 0 {
            if let userSession = allUserSessions[sessionUUID] {
                return userSession
            }
        }

        let userSession = T(sessionUUID: sessionUUID)
        allUserSessions[userSession.unsafeSessionUUID] = userSession
        return userSession
    }

    func end(_ sessionUUID: String) {
        lock.lock()
        if let userSession = allUserSessions[sessionUUID] {
            userSession.unsafeSessionClosed = true
        }
        allUserSessions.removeValue(forKey: sessionUUID)
        lock.unlock()
    }
}
