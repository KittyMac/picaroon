import Flynn
import Foundation
import Socket

public typealias GetUserSessionCallback = (UserSession?) -> Void

protocol AnyUserSessionManager {
    func get(_ cookieSessionUUID: String?, _ windowSessionUUID: String?) -> UserSession
    func end(_ userSession: UserSession)
}

public class UserSessionManager<T: UserSession>: AnyUserSessionManager {

    private var windowUserSessions: [String: UserSession] = [:]
    private var allUserSessions: [String: UserSession] = [:]
    private var lock = NSLock()

    func get(_ cookieSessionUUID: String?, _ windowSessionUUID: String?) -> UserSession {
        lock.lock()
        defer {
            lock.unlock()
        }

        if let cookieSessionUUID = cookieSessionUUID,
           let windowSessionUUID = windowSessionUUID,
           let userSession = allUserSessions[cookieSessionUUID + windowSessionUUID] {
            return userSession
        }
        if let windowSessionUUID = windowSessionUUID,
           let userSession = windowUserSessions[windowSessionUUID] {
            return userSession
        }

        let userSession = T(cookieSessionUUID: cookieSessionUUID,
                            windowSessionUUID: windowSessionUUID)
        allUserSessions[userSession.unsafeSessionUUID] = userSession
        windowUserSessions[userSession.unsafeWindowSessionUUID] = userSession
        return userSession
    }

    func end(_ userSession: UserSession) {
        lock.lock()

        if let userSession = allUserSessions[userSession.unsafeSessionUUID] {
            userSession.unsafeSessionClosed = true
        }

        allUserSessions.removeValue(forKey: userSession.unsafeSessionUUID)
        windowUserSessions.removeValue(forKey: userSession.unsafeWindowSessionUUID)

        lock.unlock()
    }
}
