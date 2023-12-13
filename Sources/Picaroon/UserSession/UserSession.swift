import Flynn
import Foundation
import Hitch

extension UUID {
    public var uuidHitch: Hitch {
        return Hitch(string: self.uuidString)
    }
}

// swiftlint:disable function_parameter_count
// swiftlint:disable line_length

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

    var unsafeCookieSessionUUID: Hitch {
        return cookieSessionUUID
    }

    private var sessionUUID: Hitch
    private var cookieSessionUUID: Hitch
    private var javascriptSessionUUID: Hitch

    private var allowReassociationFromDate: Date?
    
    var unsafeSessionHeaders: [Hitch] = []
    
    private let lastActivityLock = NSLock()
    private var lastActivity: Date = Date()
    public var safeSessionActivityTimeout: TimeInterval
    
    func unsafeIsExpired() -> Bool {
        lastActivityLock.lock(); defer { lastActivityLock.unlock() }
        return abs(lastActivity.timeIntervalSinceNow) > safeSessionActivityTimeout
    }
    
    func unsafeLastActivity() -> Date {
        lastActivityLock.lock();
        let date = lastActivity
        lastActivityLock.unlock()
        return date
    }

    func unsafeReassociationIsAllowed() -> Bool {
        guard let date = allowReassociationFromDate else { return false }
        allowReassociationFromDate = nil
        return abs(date.timeIntervalSinceNow) < 5 * 60
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

    internal func _beHandleRequest(connection: AnyConnection,
                                   httpRequest: HttpRequest) {
        if safeHandleServiceRequest(connection: connection,
                                    httpRequest: httpRequest) {
            lastActivity = Date()
            return
        }
        
        safeHandleRequest(connection: connection,
                          httpRequest: httpRequest)
    }

    internal func _beAllowReassociation() {
        allowReassociationFromDate = Date()
    }
}
