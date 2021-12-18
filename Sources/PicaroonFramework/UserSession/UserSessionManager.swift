import Flynn
import Foundation
import Socket

public typealias GetUserSessionCallback = (UserSession?) -> Void

protocol AnyUserSessionManager {
    func reassociate(cookieSessionUUID: String?,
                     _ oldJavascriptSessionUUID: String,
                     _ newJavascriptSessionUUID: String) -> UserSession?
    func get(_ cookieSessionUUID: String?, _ javascriptSessionUUID: String) -> UserSession?
    func end(_ userSession: UserSession)
}

public class UserSessionManager<T: UserSession>: AnyUserSessionManager {

    private let config: ServerConfig

    private var sessionsByJavascriptSessionUUID: [String: UserSession] = [:]
    private var sessionsByCookieSessionUUID: [String: UserSession] = [:]
    private var sessionsByCombinedSessionUUID: [String: UserSession] = [:]
    private var lock = NSLock()

    class func combined(_ cookieSessionUUID: String, _ javascriptSessionUUID: String) -> String {
        return "\(cookieSessionUUID)|\(javascriptSessionUUID)"
    }

    init(config: ServerConfig) {
        self.config = config
    }

    public func numberOfUserSessions() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return sessionsByCombinedSessionUUID.count
    }

    func reassociate(cookieSessionUUID: String?,
                     _ oldJavascriptSessionUUID: String,
                     _ newJavascriptSessionUUID: String) -> UserSession? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return self.reassociate(cookieSessionUUID: cookieSessionUUID,
                                old: oldJavascriptSessionUUID,
                                new: newJavascriptSessionUUID)
    }

    private func reassociate(cookieSessionUUID: String?,
                             old oldJavascriptSessionUUID: String,
                             new newJavascriptSessionUUID: String) -> UserSession? {

        // protect callers from trying to reassociation a session which already exists verbatim
        if let cookieSessionUUID = cookieSessionUUID {
            let newSessionUUID = Self.combined(cookieSessionUUID, newJavascriptSessionUUID)
            if let userSession = sessionsByCombinedSessionUUID[newSessionUUID] {
                return userSession
            }
        }

        if let userSession = sessionsByJavascriptSessionUUID[oldJavascriptSessionUUID],
           userSession.unsafeReassociationIsAllowed() {
            let newCookieSessionUUID = cookieSessionUUID ?? userSession.unsafeCookieSessionUUID

            // let newSessionUUID = Self.combined(newCookieSessionUUID, newJavascriptSessionUUID)
            // print("REASSOCIATING SESSION: \(userSession.unsafeSessionUUID) -> \(newSessionUUID)")

            sessionsByCombinedSessionUUID.removeValue(forKey: userSession.unsafeSessionUUID)
            sessionsByJavascriptSessionUUID.removeValue(forKey: oldJavascriptSessionUUID)
            sessionsByCookieSessionUUID.removeValue(forKey: userSession.unsafeCookieSessionUUID)

            userSession.unsafeUpdateSessionUUIDs(newCookieSessionUUID, newJavascriptSessionUUID)

            sessionsByCombinedSessionUUID[userSession.unsafeSessionUUID] = userSession
            sessionsByJavascriptSessionUUID[userSession.unsafeJavascriptSessionUUID] = userSession
            sessionsByCookieSessionUUID[userSession.unsafeCookieSessionUUID] = userSession

            return userSession
        }

        return nil
    }

    func get(_ cookieSessionUUID: String?, _ javascriptSessionUUID: String) -> UserSession? {
        lock.lock()
        defer {
            lock.unlock()
        }

        let localCookieSessionUUID = cookieSessionUUID ?? UUID().uuidString
        let combinedSessionUUID = Self.combined(localCookieSessionUUID, javascriptSessionUUID)

        // happy path: we have both cookies, and we have a user session which matches that unique session UUID
        if let userSession = sessionsByCombinedSessionUUID[combinedSessionUUID] {
            // print("HAPPY PATH 1: \(userSession.unsafeSessionUUID)")
            return userSession
        }

        // Second happy path: we have a cookie session UUID match
        if config.sessionPer == .browser {
            if let userSession = sessionsByCookieSessionUUID[localCookieSessionUUID] {
                // print("HAPPY PATH 2: \(userSession.unsafeSessionUUID)")
                return userSession
            }
        }

        // Potential reassociation path: we have a javascript sessionUUID but no matching cookie sessionUUID.
        // We allow a user's session to be reassociated to a new cookie sessionUUID under specific
        // circumstances which have not yet been firmly defined.
        if let userSession = reassociate(cookieSessionUUID: localCookieSessionUUID,
                                         old: javascriptSessionUUID,
                                         new: javascriptSessionUUID) {
            return userSession
        }

        // Otherwise, this must be a new incoming session
        let userSession = T(cookieSessionUUID: localCookieSessionUUID,
                            javascriptSessionUUID: javascriptSessionUUID)
        // print("CREATING NEW USER SESSION: \(userSession.unsafeSessionUUID)")
        sessionsByCombinedSessionUUID[userSession.unsafeSessionUUID] = userSession
        sessionsByCookieSessionUUID[userSession.unsafeCookieSessionUUID] = userSession
        sessionsByJavascriptSessionUUID[userSession.unsafeJavascriptSessionUUID] = userSession
        return userSession
    }

    func end(_ userSession: UserSession) {
        lock.lock()

        if let userSession = sessionsByCombinedSessionUUID[userSession.unsafeSessionUUID] {
            userSession.unsafeSessionClosed = true
        }

        sessionsByCombinedSessionUUID.removeValue(forKey: userSession.unsafeSessionUUID)
        sessionsByCookieSessionUUID.removeValue(forKey: userSession.unsafeJavascriptSessionUUID)
        sessionsByJavascriptSessionUUID.removeValue(forKey: userSession.unsafeJavascriptSessionUUID)

        lock.unlock()
    }
}
