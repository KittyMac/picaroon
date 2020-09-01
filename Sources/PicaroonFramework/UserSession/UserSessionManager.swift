import Flynn
import FlynnHttp
import Foundation
import Socket

public typealias GetUserSessionCallback = (Picaroon.UserSession?) -> Void

protocol AnyUserSessionManager {
    func get(_ sessionUUID: String?) -> Picaroon.UserSession
}

extension Picaroon {
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

            let userSession = T()
            allUserSessions[userSession.unsafeSessionUUID.description] = userSession
            return userSession
        }

        func endUserSession(_ sessionUUID: String) {
            lock.lock()
            allUserSessions.removeValue(forKey: sessionUUID)
            lock.unlock()
        }
    }
}
