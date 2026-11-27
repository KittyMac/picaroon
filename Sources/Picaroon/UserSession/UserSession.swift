// flynn:ignore Access Level Violation

import Flynn
import Foundation
import Hitch

extension UUID {
    public var uuidHitch: Hitch {
        return Hitch(string: self.uuidString)
    }
}

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// In Picaroon, a user sessions encapsulates on browser's "session" with the server. So when
/// the clinet connects for the very first time, a unique user session is created and assigned
/// to the connection. A cookie is used to store the user session uuid, so it is for multiple
/// connections to utilize the same user session.
///
/// UserSessions are intented to be subclassed by the application code
///
open class UserSession: Actor {

    public static func == (lhs: UserSession, rhs: UserSession) -> Bool {
        return lhs.unsafeSessionUUID == rhs.unsafeSessionUUID
    }
    
    public var unsafeSessionUUID: Hitch {
        return sessionUUID
    }
    public var unsafeJavascriptSessionUUID: Hitch {
        return javascriptSessionUUID
    }

    public var unsafeCookieSessionUUID: Hitch {
        return cookieSessionUUID
    }

    private var sessionUUID: Hitch
    private var cookieSessionUUID: Hitch
    private var javascriptSessionUUID: Hitch

    // Set by the UserSessionManager which owns this session. Reassociation tokens live in the
    // manager (under its lock), never on the session itself.
    internal weak var unsafeReassociationIssuer: ReassociationTokenIssuer?
    
    var unsafeSessionHeaders: [Hitch] = []
    
    private var lastActivityEpoch: TimeInterval = Date().timeIntervalSince1970
    public var safeSessionActivityTimeout: TimeInterval
    
    public var unsafeExpirationCode: Int = 0
    
    func unsafeIsExpired() -> Bool {
        return Date().timeIntervalSince1970 > (lastActivityEpoch + safeSessionActivityTimeout)
    }
    
    func unsafeActivityTimeoutEpoch() -> TimeInterval {
        return lastActivityEpoch + safeSessionActivityTimeout
    }
    
    func unsafeUpdateSessionUUIDs(_ cookieSessionUUID: Hitch?,
                                  _ javascriptSessionUUID: Hitch?) {
        self.cookieSessionUUID = cookieSessionUUID ?? UUID().uuidHitch
        self.javascriptSessionUUID = javascriptSessionUUID ?? UUID().uuidHitch
        sessionUUID = UserSessionManager.combined(unsafeCookieSessionUUID, unsafeJavascriptSessionUUID)
    }

    required public override init() {
        cookieSessionUUID = UUID().uuidHitch
        javascriptSessionUUID = UUID().uuidHitch
        self.safeSessionActivityTimeout = 60 * 60
        sessionUUID = UserSessionManager.combined(cookieSessionUUID, javascriptSessionUUID)
        super.init()
    }

    required public init(cookieSessionUUID: Hitch?,
                         javascriptSessionUUID: Hitch?,
                         sessionActivityTimeout: TimeInterval) {
        self.cookieSessionUUID = cookieSessionUUID ?? UUID().uuidHitch
        self.javascriptSessionUUID = javascriptSessionUUID ?? UUID().uuidHitch
        self.safeSessionActivityTimeout = sessionActivityTimeout
        sessionUUID = UserSessionManager.combined(self.cookieSessionUUID, self.javascriptSessionUUID)
        super.init()
    }
    
    open func safeHandleServiceRequest(connection: AnyConnection,
                                       httpRequest: HttpRequest) -> Bool {
        return false
    }

    open func safeHandleRequest(connection: AnyConnection,
                                httpRequest: HttpRequest) {
        connection.beSendInternalError()
    }
    
    internal func _beSetSessionHeaders(headers: [Hitch]) {
        unsafeSessionHeaders = headers
    }

    internal func _beHandleRequest(connection: AnyConnection,
                                   httpRequest: HttpRequest) {
        if safeHandleServiceRequest(connection: connection,
                                    httpRequest: httpRequest) {
            lastActivityEpoch = Date().timeIntervalSince1970
            return
        }
        
        safeHandleRequest(connection: connection,
                          httpRequest: httpRequest)
    }

    /// Allow this session to be picked up by a client which no longer has its cookie (for example
    /// the browser is coming back from a third party login). Returns a single-use reassociation
    /// token, or nil if this session is no longer live. Pass the token back to the server as the
    /// `sid` url parameter (ideally carried through the third party's `state` parameter).
    ///
    /// The token is unrelated to the session's own identifiers, works exactly once, expires after
    /// `timeout` seconds, and replaces any token previously issued for this session. Redeeming it
    /// rotates both of the session's identifiers.
    ///
    /// Call this from within the session (ie from safeHandleRequest); from elsewhere use
    /// beAllowReassociation(sender) { token in ... }.
    public func unsafeAllowReassociation(timeout: TimeInterval = 120) -> Hitch? {
        return unsafeReassociationIssuer?.issueReassociationToken(for: self, timeout: timeout)
    }

    /// Issue a token which lets a navigation (a file download, a link, an iframe) reach this session.
    /// Navigations cannot carry the Session-Id header, so in .window mode the cookie alone would land in a
    /// fresh session; put the token in the url as `sid` instead (ie /download/report.pdf?sid=<token>).
    ///
    /// The token only works together with this session's own cookie, so a leaked url is useless from any
    /// other browser. It never moves the session or rotates its identifiers. It expires after `timeout`
    /// seconds; by default it may be used repeatedly until then (browsers sometimes re-request downloads),
    /// or exactly once with `singleUse`. Issue tokens when they are needed (ie on click) rather than
    /// rendering them into pages ahead of time. Returns nil if this session is no longer live.
    ///
    /// Call this from within the session; from elsewhere use beIssueAccessToken(timeout:singleUse:sender) { token in ... }.
    public func unsafeIssueAccessToken(timeout: TimeInterval = 60, singleUse: Bool = false) -> Hitch? {
        return unsafeReassociationIssuer?.issueAccessToken(for: self, timeout: timeout, singleUse: singleUse)
    }

    internal func _beIssueAccessToken(timeout: TimeInterval, singleUse: Bool) -> Hitch? {
        return unsafeIssueAccessToken(timeout: timeout, singleUse: singleUse)
    }

    internal func _beAllowReassociation() -> Hitch? {
        return unsafeAllowReassociation()
    }
}
