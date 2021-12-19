import Flynn
import Foundation
import Socket

// swiftlint:disable function_parameter_count
// swiftlint:disable line_length

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ReassociationType {
    case oldToNew
    case javascriptSessionUUIDOnly
}

open class UserSession: Actor, Equatable {
    // In Picaroon, a user sessions encapsulates on browser's "session" with the server. So when
    // the clinet connects for the very first time, a unique user session is created and assigned
    // to the connection. A cookie is used to store the user session uuid, so it is for multiple
    // connections to utilize the same user session.

    // UserSessions are intented to be subclassed by the application code

    // unsafeSessionUUID is a UUID assigned to this session. Client is expected to query this value
    // and then send it back in future http headers to identify it (preferable in HTML5 session storage).

    public static func == (lhs: UserSession, rhs: UserSession) -> Bool {
        if lhs.unsafeSessionUUID == rhs.unsafeSessionUUID {
            return true
        }
        return false
    }

    public var unsafeSessionUUID: String {
        return sessionUUID
    }
    var unsafeCookieSessionUUID: String {
        return cookieSessionUUID
    }
    var unsafeJavascriptSessionUUID: String {
        return javascriptSessionUUID
    }

    private var sessionUUID: String
    private var cookieSessionUUID: String
    private var javascriptSessionUUID: String

    var unsafeSessionClosed: Bool = false
    private var unsafeAllowReassociationFromDate: Date?
    private var reassociationCount: Int = 0

    var unsafeSessionHeaders: [String] = []

    func unsafeReassociationIsAllowed(type: ReassociationType) -> Bool {
        guard let date = unsafeAllowReassociationFromDate else { return false }
        guard abs(date.timeIntervalSinceNow) < 5 * 60 else { return false }

        reassociationCount += 1

        // If we reassociated and we have both the old JS sessionUUID and the new JS sessionUUID,
        // then there is nothing further we need and this reassociation can end
        if type == .oldToNew && reassociationCount >= 1 {
            unsafeAllowReassociationFromDate = nil
        }

        // We are attempting reassociation when we only have the old JS sessionUUID. We need to allow
        // reassociation over two calls, the first one to return the server session cookie to the
        // client and the second one to link the new JS sessionUUID to the user session
        if type == .javascriptSessionUUIDOnly && reassociationCount >= 2 {
            unsafeAllowReassociationFromDate = nil
        }

        return true
    }

    func unsafeAllowReassociation() {
        reassociationCount = 0
        unsafeAllowReassociationFromDate = Date()
    }

    func unsafeUpdateSessionUUIDs(_ cookieSessionUUID: String?, _ javascriptSessionUUID: String?) {
        self.cookieSessionUUID = cookieSessionUUID ?? UUID().uuidString
        self.javascriptSessionUUID = javascriptSessionUUID ?? UUID().uuidString
        sessionUUID = UserSessionManager.combined(unsafeCookieSessionUUID, unsafeJavascriptSessionUUID)
    }

    required public override init() {
        cookieSessionUUID = UUID().uuidString
        javascriptSessionUUID = UUID().uuidString
        sessionUUID = UserSessionManager.combined(cookieSessionUUID, javascriptSessionUUID)
        super.init()
    }

    required public init(cookieSessionUUID: String?, javascriptSessionUUID: String?) {
        self.cookieSessionUUID = cookieSessionUUID ?? UUID().uuidString
        self.javascriptSessionUUID = javascriptSessionUUID ?? UUID().uuidString
        sessionUUID = UserSessionManager.combined(self.cookieSessionUUID, self.javascriptSessionUUID)
        super.init()
    }

    open func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
        connection.beSendInternalError()
    }

    private func _beHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
        safeHandleRequest(connection, httpRequest)
    }

    private func _beAllowReassociation() {
        unsafeAllowReassociation()
    }

    private func _beUrlRequest(url: String,
                               httpMethod: String,
                               params: [String: String],
                               headers: [String: String],
                               body: Data?,
                               _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {

        guard var components = URLComponents(string: url) else {
            return returnCallback(nil, nil, "failed to create url components")
        }

        if components.queryItems == nil {
            components.queryItems = []
        }

        params.forEach { (key, value) in
            components.queryItems?.append(URLQueryItem(name: key, value: value))
        }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        guard let url = components.url else { return returnCallback(nil, nil, "failed to get components url") }

        var request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 30.0)

        request.httpMethod = httpMethod
        request.httpBody = body
        request.httpShouldHandleCookies = false

        for (header, value) in headers {
            request.addValue(value, forHTTPHeaderField: header)
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let response = response as? HTTPURLResponse else {
                return returnCallback(nil, nil, "response is not an http url response")
            }
            guard let data = data else { return returnCallback(nil, response, "response data is nil") }
            guard error == nil else { return returnCallback(nil, response, "\(error!)") }

            if response.statusCode >= 200 && response.statusCode <= 299 {
                returnCallback(data, response, nil)
            } else {
                returnCallback(data, response, "http \(response.statusCode)")
            }
        }
        task.resume()

    }
}

// MARK: - Autogenerated by FlynnLint
// Contents of file after this marker will be overwritten as needed

extension UserSession {

    @discardableResult
    public func beHandleRequest(_ connection: AnyConnection,
                                _ httpRequest: HttpRequest) -> Self {
        unsafeSend { self._beHandleRequest(connection, httpRequest) }
        return self
    }
    @discardableResult
    public func beAllowReassociation() -> Self {
        unsafeSend(_beAllowReassociation)
        return self
    }
    @discardableResult
    public func beUrlRequest(url: String,
                             httpMethod: String,
                             params: [String: String],
                             headers: [String: String],
                             body: Data?,
                             _ sender: Actor,
                             _ callback: @escaping ((Data?, HTTPURLResponse?, String?) -> Void)) -> Self {
        unsafeSend {
            self._beUrlRequest(url: url, httpMethod: httpMethod, params: params, headers: headers, body: body) { arg0, arg1, arg2 in
                sender.unsafeSend {
                    callback(arg0, arg1, arg2)
                }
            }
        }
        return self
    }

}
