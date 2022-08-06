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
open class UserSession: Actor, Equatable {

    public static func == (lhs: UserSession, rhs: UserSession) -> Bool {
        if lhs.unsafeSessionUUID == rhs.unsafeSessionUUID {
            return true
        }
        return false
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

    func unsafeReassociationIsAllowed() -> Bool {
        guard let date = allowReassociationFromDate else { return false }
        allowReassociationFromDate = nil
        return abs(date.timeIntervalSinceNow) < 5 * 60
    }

    func unsafeUpdateSessionUUIDs(_ cookieSessionUUID: Hitch?, _ javascriptSessionUUID: Hitch?) {
        self.cookieSessionUUID = cookieSessionUUID ?? UUID().uuidHitch
        self.javascriptSessionUUID = javascriptSessionUUID ?? UUID().uuidHitch
        sessionUUID = UserSessionManager.combined(unsafeCookieSessionUUID, unsafeJavascriptSessionUUID)
    }

    required public override init() {
        cookieSessionUUID = UUID().uuidHitch
        javascriptSessionUUID = UUID().uuidHitch
        sessionUUID = UserSessionManager.combined(cookieSessionUUID, javascriptSessionUUID)
        super.init()
    }

    required public init(cookieSessionUUID: Hitch?, javascriptSessionUUID: Hitch?) {
        self.cookieSessionUUID = cookieSessionUUID ?? UUID().uuidHitch
        self.javascriptSessionUUID = javascriptSessionUUID ?? UUID().uuidHitch
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
            return
        }
        
        safeHandleRequest(connection: connection,
                          httpRequest: httpRequest)
    }

    internal func _beAllowReassociation() {
        allowReassociationFromDate = Date()
    }
}
