import Flynn
import Foundation
import Hitch

public typealias GetUserSessionCallback = (UserSession?) -> Void

public protocol AnyUserSessionManager {
    func reassociate(cookieSessionUUID: Hitch?,
                     _ oldJavascriptSessionUUID: Hitch,
                     _ newJavascriptSessionUUID: Hitch) -> UserSession?
    func get(_ cookieSessionUUID: Hitch?, _ javascriptSessionUUID: Hitch?) -> UserSession?
    func end(_ userSession: UserSession)
}

public class UserSessionManager<T: UserSession>: AnyUserSessionManager {

    private let config: ServerConfig

    private var sessionsByJavascriptSessionUUID: [Hitch: UserSession] = [:]
    private var sessionsByCookieSessionUUID: [Hitch: UserSession] = [:]
    private var sessionsByCombinedSessionUUID: [Hitch: UserSession] = [:]
    private var lock = NSLock()

    class func combined(_ cookieSessionUUID: Hitch, _ javascriptSessionUUID: Hitch) -> Hitch {
        let combined = Hitch(capacity: 80)
        combined.append(cookieSessionUUID)
        combined.append(.pipe)
        combined.append(javascriptSessionUUID)
        return combined
    }

    init(config: ServerConfig) {
        self.config = config
        
        Flynn.Timer(timeInterval: 30, immediate: false, repeats: true, Flynn.any) { [weak self] _ in
            self?.checkExpiredSessions()
        }
    }

    public func numberOfUserSessions() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return sessionsByCombinedSessionUUID.count
    }

    public func reassociate(cookieSessionUUID: Hitch?,
                            _ oldJavascriptSessionUUID: Hitch,
                            _ newJavascriptSessionUUID: Hitch) -> UserSession? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return self.reassociate(cookieSessionUUID: cookieSessionUUID,
                                old: oldJavascriptSessionUUID,
                                new: newJavascriptSessionUUID)
    }
    
    private func checkExpiredSessions() {
        lock.lock()
        
        // Remove any inactive sessions
        for userSession in sessionsByCombinedSessionUUID.values where userSession.unsafeIsExpired() {
            sessionsByCombinedSessionUUID.removeValue(forKey: userSession.unsafeSessionUUID)
            sessionsByCookieSessionUUID.removeValue(forKey: userSession.unsafeCookieSessionUUID)
            sessionsByJavascriptSessionUUID.removeValue(forKey: userSession.unsafeJavascriptSessionUUID)
            ConnectionManager.shared.beClose(session: userSession)
        }
        
        // Remove the most inactive sessions until we get back under our maximum
        if sessionsByCombinedSessionUUID.count > config.maximumSessions {
            var sorted = sessionsByCombinedSessionUUID.values.sorted(by: {  $0.unsafeLastActivity() < $1.unsafeLastActivity() })
            while sessionsByCombinedSessionUUID.count > config.maximumSessions && sorted.count > 0 {
                let userSession = sorted.removeFirst()
                sessionsByCombinedSessionUUID.removeValue(forKey: userSession.unsafeSessionUUID)
                sessionsByCookieSessionUUID.removeValue(forKey: userSession.unsafeCookieSessionUUID)
                sessionsByJavascriptSessionUUID.removeValue(forKey: userSession.unsafeJavascriptSessionUUID)
                ConnectionManager.shared.beClose(session: userSession)
            }
        }
        
        lock.unlock()
    }

    private func reassociate(cookieSessionUUID: Hitch?,
                             old oldJavascriptSessionUUID: Hitch,
                             new newJavascriptSessionUUID: Hitch) -> UserSession? {

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
            //print("REASSOCIATING SESSION: \(userSession.unsafeSessionUUID) -> \(newCookieSessionUUID)")

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

    public func get(_ cookieSessionUUID: Hitch?,
                    _ javascriptSessionUUID: Hitch?) -> UserSession? {
        lock.lock()
        defer {
            lock.unlock()
        }

        let localJavascriptSessionUUID = javascriptSessionUUID ?? UUID().uuidHitch

        let localCookieSessionUUID = cookieSessionUUID ?? UUID().uuidHitch
        let combinedSessionUUID = Self.combined(localCookieSessionUUID, localJavascriptSessionUUID)

        // happy path 1: we have a session UUID match and that's all we care about
        if config.sessionPer == .api {
            if let userSession = sessionsByJavascriptSessionUUID[localJavascriptSessionUUID] {
                //print("HAPPY PATH 1: \(userSession.unsafeSessionUUID)")
                return userSession
            }
        }
        
        // happy path 2: we have both cookies, and we have a user session which matches that unique session UUID
        if let userSession = sessionsByCombinedSessionUUID[combinedSessionUUID] {
            //print("HAPPY PATH 2: \(userSession.unsafeSessionUUID)")
            return userSession
        }

        // happy path 3: we have a cookie session UUID match
        if config.sessionPer == .browser {
            if let userSession = sessionsByCookieSessionUUID[localCookieSessionUUID] {
                //print("HAPPY PATH 3: \(userSession.unsafeSessionUUID)")
                return userSession
            }
        }

        // Potential reassociation path: we have a javascript sessionUUID but no matching cookie sessionUUID.
        // We allow a user's session to be reassociated to a new cookie sessionUUID under limited circumstances
        if javascriptSessionUUID != nil {
            if let userSession = reassociate(cookieSessionUUID: localCookieSessionUUID,
                                             old: localJavascriptSessionUUID,
                                             new: localJavascriptSessionUUID) {
                return userSession
            }
        }

        // Otherwise, this must be a new incoming session
        let userSession = T(cookieSessionUUID: localCookieSessionUUID,
                            javascriptSessionUUID: localJavascriptSessionUUID,
                            sessionActivityTimeout: config.sessionActivityTimeout)
        //print("CREATING NEW USER SESSION: \(userSession.unsafeSessionUUID)")
        sessionsByCombinedSessionUUID[userSession.unsafeSessionUUID] = userSession
        sessionsByCookieSessionUUID[userSession.unsafeCookieSessionUUID] = userSession
        sessionsByJavascriptSessionUUID[userSession.unsafeJavascriptSessionUUID] = userSession
        return userSession
    }

    public func end(_ userSession: UserSession) {
        lock.lock()

        sessionsByCombinedSessionUUID.removeValue(forKey: userSession.unsafeSessionUUID)
        sessionsByCookieSessionUUID.removeValue(forKey: userSession.unsafeCookieSessionUUID)
        sessionsByJavascriptSessionUUID.removeValue(forKey: userSession.unsafeJavascriptSessionUUID)
        ConnectionManager.shared.beClose(session: userSession)

        lock.unlock()
    }
}
