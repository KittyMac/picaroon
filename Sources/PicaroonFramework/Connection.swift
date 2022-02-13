import Flynn
import Foundation
import Hitch

// swiftlint:disable function_body_length
// swiftlint:disable line_length
// swiftlint:disable cyclomatic_complexity

public protocol AnyConnection {
    @discardableResult func beSetTimeout(_ timeout: TimeInterval) -> Self
    @discardableResult func beSend(httpResponse: HttpResponse) -> Self
    @discardableResult func beSendIfModified(httpRequest: HttpRequest,
                                             httpResponse: HttpResponse) -> Self
    @discardableResult func beEndUserSession() -> Self
    @discardableResult func beSendInternalError() -> Self
    @discardableResult func beSendServiceUnavailable() -> Self
    @discardableResult func beSendSuccess(_ message: Hitch) -> Self
    @discardableResult func beSendError(_ error: Hitch) -> Self
    @discardableResult func beSendNotModified() -> Self
}

public class Connection: Actor, AnyConnection {

    // Handle a single TCP connection to a client. Multiple connections can link to the
    // same UserSession.

    private let socket: Socket

    private var timeout: TimeInterval = 30.0

    private var lastCommunicationTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    private var bufferSize = 1024 * 1024 * 2
    private var buffer: UnsafeMutablePointer<UInt8>
    private let endPtr: UnsafeMutablePointer<UInt8>
    private var currentPtr: UnsafeMutablePointer<UInt8>

    private var userSession: UserSession?
    private let userSessionManager: AnyUserSessionManager

    private let staticStorageHandler: StaticStorageHandler?

    @usableFromInline
    var safeCheckForMoreDataScheduled = false

    init(socket: Socket,
         config: ServerConfig,
         staticStorageHandler: StaticStorageHandler?,
         userSessionManager: AnyUserSessionManager) {
        self.socket = socket
        self.userSessionManager = userSessionManager
        self.staticStorageHandler = staticStorageHandler

        socket.setReadTimeout(milliseconds: 5)
        
        timeout = config.requestTimeout
        bufferSize = config.maxRequestInBytes

        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize + 32)
        buffer.initialize(to: 0)

        currentPtr = buffer
        endPtr = buffer + bufferSize

        super.init()

        unsafeMessageBatchSize = 1

        safeCheckForMoreDataIfNeeded()
    }

    deinit {
        buffer.deallocate()
    }

    private func _beSetTimeout(_ timeout: TimeInterval) {
        self.timeout = timeout
    }
    
    private func _beSend(httpResponse: HttpResponse) {
        httpResponse.send(socket: socket,
                          userSession: userSession)

        // If we write data, then we should expect to read data
        safeCheckForMoreDataIfNeeded()
    }

    private func _beSendIfModified(httpRequest: HttpRequest,
                                   httpResponse: HttpResponse) {
#if DEBUG
        _beSend(httpResponse: httpResponse)
#else
        if httpResponse.isNew(httpRequest) {
            httpResponse.send(socket: socket,
                              userSession: userSession)
            safeCheckForMoreDataIfNeeded()
        } else {
            _beSendNotModified()
        }
#endif
    }

    private func _beEndUserSession() {
        if let userSession = userSession {
            userSessionManager.end(userSession)
        }
        userSession = nil
    }

    private func _beSendInternalError() {
        _beSend(httpResponse: HttpStaticResponse.internalServerError)
    }

    private func _beSendServiceUnavailable() {
        _beSend(httpResponse: HttpStaticResponse.serviceUnavailable)
    }

    private func _beSendSuccess(_ message: Hitch = "success") {
        _beSend(httpResponse: HttpResponse(text: message))
    }

    private func _beSendError(_ error: Hitch) {
        _beSend(httpResponse: HttpResponse(status: .badRequest,
                                           type: .txt,
                                           payload: error))
    }

    private func _beSendNotModified() {
        _beSend(httpResponse: HttpResponse(status: .notModified,
                                           type: .txt,
                                           payload: "not modified"))
    }

    @inlinable @inline(__always)
    internal func safeCheckForMoreDataIfNeeded() {
        if safeCheckForMoreDataScheduled == false {
            safeCheckForMoreDataScheduled = true
            unsafeSend { self.safeCheckForMoreData() }
        }
    }

    @usableFromInline
    func safeCheckForMoreData() {

        safeCheckForMoreDataScheduled = false

        // Checks the socket to see if there is an HTTP command ready to be processed.
        // Whether we process one or not, we call beNextCommand() to check again in
        // the future for another command.
        if socket.isClosed() {
            return
        }

        // Read some data onto the current buffer position
        let bytesRead = socket.recv(bytes: currentPtr,
                                    count: (endPtr - currentPtr))
        if bytesRead < 0 {
            return
        }
        if bytesRead == 0 {
            if ProcessInfo.processInfo.systemUptime - lastCommunicationTime > timeout {
                _beSendInternalError()
                socket.close()
                return
            }

            safeCheckForMoreDataIfNeeded()
            return
        }

        lastCommunicationTime = ProcessInfo.processInfo.systemUptime

        currentPtr += bytesRead

        // if we're reading more data than our buffer allows, end the connection
        if currentPtr >= endPtr {
            _beSendInternalError()
            socket.close()
            return
        }

        // See if it is complete http request; if it is incomplete, we wait until we get more data
        guard let httpRequest = HttpRequest(request: buffer,
                                            size: currentPtr - buffer + 1) else {
            // We have an incomplete https request, wait for more data and try again
            safeCheckForMoreDataIfNeeded()
            return
        }

        // reset current pointer to be read for the next http request
        currentPtr = buffer

        // First allow the static storage handler to handle it. It is the responsibility of the host site to
        // let reassociations (ie url param sid) to fall through and be handled by a user session. This is
        // critical because only the one call will have the sid reassociation parameter, and that one call
        // will need to ensure the return passes back the correct session UUIDs
        if  let staticStorageHandler = self.staticStorageHandler,
            let httpResponse = staticStorageHandler(httpRequest) {
            _beSendIfModified(httpRequest: httpRequest,
                              httpResponse: httpResponse)
            return
        }

        // Here's how we attempt to link sessions to web clients:
        // 1. Picaroon assigns a HTTP only cookieSessionUUID. These cookies are not accessible from javascript and
        //    provide the main linking of UserSession actor to the web session
        // 2. The client javascript can choose to send a "Session-Id" in Ajax request JSON.
        //    This value is used to help transition a user session from one web session to another (because page reloads
        //    will result in the cookieSessionUUID potentially changing.
        // 3. The url may have a sessionId embedded as "sid" in the url parameters. This sessionId may or may not
        //    be the "Session-Id" the javascript is passing in. An "sid" passed in basically means "find the user
        //    session whose jsavascript session id matches it and set it to session id
        // 3. Reassociation is only allowed when the client flags the session to expect a reassociation (say, we're
        //    about to log in using a 3rd party service and that process will lose our http session cookie). This prevents
        //    malicious individuals from stealing a live session just by knowing the client-side session UUID

        let cookieSessionUUID = httpRequest.cookies[Picaroon.userSessionCookie]
        var javascriptSessionUUID = (httpRequest.sessionId ?? httpRequest.sid)?.hitch()
        let httpRequestSid = httpRequest.sid?.hitch()

        if let newJavascriptSessionUUID = javascriptSessionUUID,
           let oldJavascriptSessionUUID = httpRequestSid,
           oldJavascriptSessionUUID != newJavascriptSessionUUID {
            if let userSession = userSessionManager.reassociate(cookieSessionUUID: cookieSessionUUID,
                                                                oldJavascriptSessionUUID, newJavascriptSessionUUID) {
                self.userSession = userSession
                
                userSession.beHandleRequest(connection: self,
                                            httpRequest: httpRequest)
                return
            }
            return _beSendInternalError()
        }

        if let oldJavascriptSessionUUID = httpRequestSid {
            if let userSession = userSessionManager.reassociate(cookieSessionUUID: cookieSessionUUID,
                                                                oldJavascriptSessionUUID, oldJavascriptSessionUUID) {
                self.userSession = userSession
                
                userSession.beHandleRequest(connection: self,
                                            httpRequest: httpRequest)
                return
            }

            javascriptSessionUUID = nil
        }

        // If no session uuid of any kind was supplied by the client, then this is technically an
        // error  (it should be served by the static handler if we don't have a client which is
        // running enough to provide us a session id).
        if let userSession = userSessionManager.get(cookieSessionUUID, javascriptSessionUUID) {
            self.userSession = userSession
            
            userSession.beHandleRequest(connection: self,
                                        httpRequest: httpRequest)
            return
        }

        return _beSendInternalError()
    }
}

// MARK: - Autogenerated by FlynnLint
// Contents of file after this marker will be overwritten as needed

extension Connection {

    @discardableResult
    public func beSetTimeout(_ timeout: TimeInterval) -> Self {
        unsafeSend { self._beSetTimeout(timeout) }
        return self
    }
    @discardableResult
    public func beSend(httpResponse: HttpResponse) -> Self {
        unsafeSend { self._beSend(httpResponse: httpResponse) }
        return self
    }
    @discardableResult
    public func beSendIfModified(httpRequest: HttpRequest,
                                 httpResponse: HttpResponse) -> Self {
        unsafeSend { self._beSendIfModified(httpRequest: httpRequest, httpResponse: httpResponse) }
        return self
    }
    @discardableResult
    public func beEndUserSession() -> Self {
        unsafeSend(_beEndUserSession)
        return self
    }
    @discardableResult
    public func beSendInternalError() -> Self {
        unsafeSend(_beSendInternalError)
        return self
    }
    @discardableResult
    public func beSendServiceUnavailable() -> Self {
        unsafeSend(_beSendServiceUnavailable)
        return self
    }
    @discardableResult
    public func beSendSuccess(_ message: Hitch) -> Self {
        unsafeSend { self._beSendSuccess(message) }
        return self
    }
    @discardableResult
    public func beSendError(_ error: Hitch) -> Self {
        unsafeSend { self._beSendError(error) }
        return self
    }
    @discardableResult
    public func beSendNotModified() -> Self {
        unsafeSend(_beSendNotModified)
        return self
    }

}
