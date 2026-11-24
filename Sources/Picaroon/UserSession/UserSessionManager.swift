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

/// Session identifiers are always minted by the server. Identifiers supplied by the client
/// (cookie, Session-Id header, sid url parameter) are only ever used as lookup keys; they are
/// never used to create a new session. A cookie value is only reused for a new session when it
/// was issued by this server and still belongs to a live session (ie a second window in the same
/// browser in .window mode). A client-supplied javascript session UUID is never adopted for a new
/// session. This prevents session fixation, stops logout from silently "resurrecting" the same
/// identifiers, and stops a client from clobbering another session's index entries.
public class UserSessionManager<T: UserSession>: AnyUserSessionManager {

    private let config: ServerConfig

    private var sessionsByJavascriptSessionUUID: [Hitch: UserSession] = [:]
    // In .window mode many sessions (one per window) legitimately share the same cookie
    private var sessionsByCookieSessionUUID: [Hitch: [UserSession]] = [:]
    private var sessionsByCombinedSessionUUID: [Hitch: UserSession] = [:]
    private var lock = NSLock()

    class func combined(_ cookieSessionUUID: Hitch, _ javascriptSessionUUID: Hitch) -> Hitch {
        let combined = Hitch(capacity: 80)
        combined.append(cookieSessionUUID)
        combined.append(.pipe)
        combined.append(javascriptSessionUUID)
        return combined
    }

    /// Returns the identifier only if it is shaped exactly like a UUID string
    /// (8-4-4-4-12 hex digits). Anything else from the client is treated as absent.
    class func validated(_ uuid: Hitch?) -> Hitch? {
        guard let uuid = uuid, uuid.count == 36 else { return nil }
        for idx in 0..<36 {
            let char = uuid[idx]
            switch idx {
            case 8, 13, 18, 23:
                if char != .minus { return nil }
            default:
                let isHex = (char >= .zero && char <= .nine) ||
                            (char >= .A && char <= .F) ||
                            (char >= .a && char <= .f)
                if isHex == false { return nil }
            }
        }
        return uuid
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

    // MARK: - Index maintenance (call with lock held)

    private func unsafeIndex(_ userSession: UserSession) {
        sessionsByCombinedSessionUUID[userSession.unsafeSessionUUID] = userSession
        sessionsByJavascriptSessionUUID[userSession.unsafeJavascriptSessionUUID] = userSession
        sessionsByCookieSessionUUID[userSession.unsafeCookieSessionUUID, default: []].append(userSession)
    }

    /// Removes index entries only if they point at this exact session, so removing one
    /// session can never drop another session's entry that happens to share a key.
    private func unsafeUnindex(_ userSession: UserSession) {
        let sessionUUID = userSession.unsafeSessionUUID
        if sessionsByCombinedSessionUUID[sessionUUID] === userSession {
            sessionsByCombinedSessionUUID.removeValue(forKey: sessionUUID)
        }

        let javascriptSessionUUID = userSession.unsafeJavascriptSessionUUID
        if sessionsByJavascriptSessionUUID[javascriptSessionUUID] === userSession {
            sessionsByJavascriptSessionUUID.removeValue(forKey: javascriptSessionUUID)
        }

        let cookieSessionUUID = userSession.unsafeCookieSessionUUID
        if var sessions = sessionsByCookieSessionUUID[cookieSessionUUID] {
            sessions.removeAll { $0 === userSession }
            if sessions.isEmpty {
                sessionsByCookieSessionUUID.removeValue(forKey: cookieSessionUUID)
            } else {
                sessionsByCookieSessionUUID[cookieSessionUUID] = sessions
            }
        }
    }

    /// A cookie UUID may be reused only if this server issued it and it is still held by a live session.
    private func unsafeIsLiveCookie(_ cookieSessionUUID: Hitch?) -> Bool {
        guard let cookieSessionUUID = cookieSessionUUID else { return false }
        return sessionsByCookieSessionUUID[cookieSessionUUID]?.isEmpty == false
    }

    // MARK: - Public API

    public func reassociate(cookieSessionUUID: Hitch?,
                            _ oldJavascriptSessionUUID: Hitch,
                            _ newJavascriptSessionUUID: Hitch) -> UserSession? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return self.reassociate(cookieSessionUUID: Self.validated(cookieSessionUUID),
                                old: Self.validated(oldJavascriptSessionUUID),
                                new: Self.validated(newJavascriptSessionUUID))
    }

    private func checkExpiredSessions() {
        lock.lock()

        // Remove any inactive sessions
        for userSession in sessionsByCombinedSessionUUID.values where userSession.unsafeIsExpired() {
            userSession.unsafeExpirationCode = 1
            unsafeUnindex(userSession)
            ConnectionManager_CloseConnection(session: userSession)
        }

        // Remove the sessions with the shorted inactivity timeouts
        if sessionsByCombinedSessionUUID.count > config.maximumSessions {
            var sorted = sessionsByCombinedSessionUUID.values.sorted(by: {  $0.unsafeActivityTimeoutEpoch() < $1.unsafeActivityTimeoutEpoch() })
            while sessionsByCombinedSessionUUID.count > config.maximumSessions && sorted.count > 0 {
                let userSession = sorted.removeFirst()
                userSession.unsafeExpirationCode = 2
                unsafeUnindex(userSession)
                ConnectionManager_CloseConnection(session: userSession)
            }
        }

        lock.unlock()
    }

    /// Expects already-validated identifiers.
    private func reassociate(cookieSessionUUID: Hitch?,
                             old oldJavascriptSessionUUID: Hitch?,
                             new newJavascriptSessionUUID: Hitch?) -> UserSession? {
        guard let oldJavascriptSessionUUID = oldJavascriptSessionUUID else { return nil }

        // protect callers from trying to reassociation a session which already exists verbatim
        if let cookieSessionUUID = cookieSessionUUID,
           let newJavascriptSessionUUID = newJavascriptSessionUUID {
            let newSessionUUID = Self.combined(cookieSessionUUID, newJavascriptSessionUUID)
            if let userSession = sessionsByCombinedSessionUUID[newSessionUUID] {
                return userSession
            }
        }

        guard let userSession = sessionsByJavascriptSessionUUID[oldJavascriptSessionUUID],
              userSession.unsafeReassociationIsAllowed() else { return nil }

        // Keep the client's cookie only if we issued it and it is live; otherwise mint a new one
        // (it reaches the client through the Set-Cookie on this response).
        let newCookieSessionUUID = unsafeIsLiveCookie(cookieSessionUUID) ? cookieSessionUUID! : UUID().uuidHitch

        // If the client asked for a different javascript UUID we never adopt its value; we mint one.
        // Per the reassociation contract (see Connection) the response to the sid request is responsible
        // for handing the session's current UUIDs back to the client.
        let finalJavascriptSessionUUID = (newJavascriptSessionUUID == nil || newJavascriptSessionUUID == oldJavascriptSessionUUID) ? oldJavascriptSessionUUID : UUID().uuidHitch

        //print("REASSOCIATING SESSION: \(userSession.unsafeSessionUUID) -> \(newCookieSessionUUID)")

        userSession.unsafeExpirationCode = 3
        unsafeUnindex(userSession)
        userSession.unsafeUpdateSessionUUIDs(newCookieSessionUUID, finalJavascriptSessionUUID)
        unsafeIndex(userSession)

        return userSession
    }

    public func get(_ cookieSessionUUID: Hitch?,
                    _ javascriptSessionUUID: Hitch?) -> UserSession? {
        lock.lock()
        defer {
            lock.unlock()
        }

        let cookieSessionUUID = Self.validated(cookieSessionUUID)
        let javascriptSessionUUID = Self.validated(javascriptSessionUUID)

        // happy path 1: we have a session UUID match and that's all we care about
        if config.sessionPer == .api,
           let javascriptSessionUUID = javascriptSessionUUID,
           let userSession = sessionsByJavascriptSessionUUID[javascriptSessionUUID] {
            //print("HAPPY PATH 1: \(userSession.unsafeSessionUUID)")
            return userSession
        }

        // happy path 2: we have both cookies, and we have a user session which matches that unique session UUID
        if let cookieSessionUUID = cookieSessionUUID,
           let javascriptSessionUUID = javascriptSessionUUID,
           let userSession = sessionsByCombinedSessionUUID[Self.combined(cookieSessionUUID, javascriptSessionUUID)] {
            //print("HAPPY PATH 2: \(userSession.unsafeSessionUUID)")
            return userSession
        }

        // happy path 3: we have a cookie session UUID match
        if config.sessionPer == .browser,
           let cookieSessionUUID = cookieSessionUUID,
           let userSession = sessionsByCookieSessionUUID[cookieSessionUUID]?.first {
            //print("HAPPY PATH 3: \(userSession.unsafeSessionUUID)")
            return userSession
        }

        // Potential reassociation path: we have a javascript sessionUUID but no matching cookie sessionUUID.
        // We allow a user's session to be reassociated to a new cookie sessionUUID under limited circumstances
        if let javascriptSessionUUID = javascriptSessionUUID,
           let userSession = reassociate(cookieSessionUUID: cookieSessionUUID,
                                         old: javascriptSessionUUID,
                                         new: javascriptSessionUUID) {
            return userSession
        }

        // Otherwise, this must be a new incoming session. Its identifiers are minted here; the only
        // client value we keep is a cookie we issued that is still live (another window, same browser).
        let newCookieSessionUUID = unsafeIsLiveCookie(cookieSessionUUID) ? cookieSessionUUID! : UUID().uuidHitch
        let userSession = T(cookieSessionUUID: newCookieSessionUUID,
                            javascriptSessionUUID: UUID().uuidHitch,
                            sessionActivityTimeout: config.sessionActivityTimeout)
        //print("CREATING NEW USER SESSION: \(userSession.unsafeSessionUUID)")
        unsafeIndex(userSession)
        return userSession
    }

    public func end(_ userSession: UserSession) {
        lock.lock()

        userSession.unsafeExpirationCode = 4
        unsafeUnindex(userSession)
        ConnectionManager_CloseConnection(session: userSession)

        lock.unlock()
    }
}
