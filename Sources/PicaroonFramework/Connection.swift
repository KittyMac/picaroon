import Flynn
import Foundation
import Socket

// swiftlint:disable function_body_length
// swiftlint:disable line_length
// swiftlint:disable cyclomatic_complexity

public protocol AnyConnection {
    @discardableResult func beSendData(_ data: Data) -> Self
    @discardableResult func beSendDataIfChanged(_ httpRequest: HttpRequest, _ data: Data) -> Self
    @discardableResult func beEndUserSession() -> Self
    @discardableResult func beSendInternalError() -> Self
    @discardableResult func beSendServiceUnavailable() -> Self
    @discardableResult func beSendSuccess(_ message: String) -> Self
    @discardableResult func beSendError(_ error: String) -> Self
    @discardableResult func beSendNotModified() -> Self
    @discardableResult func beSetTimeout(_ timeout: TimeInterval) -> Self
}

public class Connection: Actor, AnyConnection {

    // Handle a single TCP connection to a client. Multiple connections can link to the
    // same UserSession.

    private let socket: Socket

    private var timeout: TimeInterval = 30.0

    private var lastCommunicationTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    private var bufferSize = 1024 * 1024 * 2
    private var buffer: UnsafeMutablePointer<CChar>
    private let endPtr: UnsafeMutablePointer<CChar>
    private var currentPtr: UnsafeMutablePointer<CChar>

    private var userSession: UserSession?
    private let userSessionManager: AnyUserSessionManager

    private let staticStorageHandler: StaticStorageHandler?

    private var checkForMoreDataScheduled = false

    init(socket: Socket,
         config: ServerConfig,
         staticStorageHandler: StaticStorageHandler?,
         userSessionManager: AnyUserSessionManager) {
        self.socket = socket
        self.userSessionManager = userSessionManager
        self.staticStorageHandler = staticStorageHandler

        try? socket.setReadTimeout(value: 5)

        timeout = config.requestTimeout
        bufferSize = config.maxRequestInBytes

        buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize + 32)
        buffer.initialize(to: 0)

        currentPtr = buffer
        endPtr = buffer + bufferSize

        super.init()

        unsafeMessageBatchSize = 1

        checkForMoreDataIfNeeded()
    }

    deinit {
        buffer.deallocate()
    }

    private func _beSetTimeout(_ timeout: TimeInterval) {
        self.timeout = timeout
    }

    private func _beSendData(_ data: Data) {
        do {
            try socket.write(from: data)
        } catch {
            socket.close()
        }

        // If we write data, then we should expect to read data
        checkForMoreDataIfNeeded()
    }

    private func _beSendDataIfChanged(_ httpRequest: HttpRequest, _ data: Data) {
#if DEBUG
        _beSendData(data)
#else
        if HttpResponse.isNew(httpRequest) {
            _beSendData(data)
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
        _beSendData(HttpResponse.asData(userSession, .internalServerError, .txt))
    }

    private func _beSendServiceUnavailable() {
        _beSendData(HttpResponse.asData(userSession, .serviceUnavailable, .txt))
    }

    private func _beSendSuccess(_ message: String = "success") {
        _beSendData(HttpResponse.asData(userSession, .ok, .txt, message))
    }

    private func _beSendError(_ error: String) {
        _beSendData(HttpResponse.asData(userSession, .badRequest, .txt, error))
    }

    private func _beSendNotModified() {
        _beSendData(HttpResponse.asData(userSession, .notModified, .txt, "not modified"))
    }

    private func checkForMoreDataIfNeeded() {
        if checkForMoreDataScheduled == false {
            checkForMoreDataScheduled = true
            unsafeSend { self.checkForMoreData() }
        }
    }

    private func checkForMoreData() {

        checkForMoreDataScheduled = false

        // Checks the socket to see if there is an HTTP command ready to be processed.
        // Whether we process one or not, we call beNextCommand() to check again in
        // the future for another command.
        if socket.remoteConnectionClosed {
            socket.close()
            return
        }

        do {
            // Read some data onto the current buffer position
            let bytesRead = try socket.read(into: currentPtr, bufSize: (endPtr - currentPtr), truncate: true)
            if bytesRead == 0 {
                if ProcessInfo.processInfo.systemUptime - lastCommunicationTime > timeout {
                    _beSendInternalError()
                    socket.close()
                    return
                }

                checkForMoreDataIfNeeded()
                return
            }

            lastCommunicationTime = ProcessInfo.processInfo.systemUptime

            currentPtr[bytesRead] = 0
            currentPtr += bytesRead

            // if we're reading more data than our buffer allows, end the connection
            if currentPtr >= endPtr {
                _beSendInternalError()
                socket.close()
                return
            }

            // See if it is complete http request; if it is incomplete, we wait until we get more data
            let httpRequest = HttpRequest(request: buffer,
                                          size: currentPtr - buffer + 1)

            // We have a complete http request, we need to process it
            if httpRequest.incomplete {
                checkForMoreDataIfNeeded()
                return
            }

            // if let requestString = String(bytesNoCopy: buffer, length: currentPtr - buffer + 1, encoding: .utf8, freeWhenDone: false) {
            //    print(requestString)
            // }

            // reset current pointer to be read for the next http request
            currentPtr = buffer

            // First allow the static storage handler to handle it
            if httpRequest.url != "/picaroon.js" && httpRequest.sid == nil {
                if  let staticStorageHandler = self.staticStorageHandler,
                    let data = staticStorageHandler(nil, httpRequest) {
                    self._beSendDataIfChanged(httpRequest, data)
                    return
                }
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
            let javascriptSessionUUID = httpRequest.sessionId ?? httpRequest.sid

            // print(">>> \(cookieSessionUUID), \(javascriptSessionUUID), \(httpRequest.method), \(httpRequest.url), \(httpRequest.urlParameters)")

            let handleRequest: (UserSession) -> Void = { userSession in
                // is this the special "picaroon.js"
                if httpRequest.method == .GET &&
                    httpRequest.url == "/picaroon.js" {
                    self._beSendData(HttpResponse.asData(userSession, .ok, .js, "sessionStorage.setItem('Session-Id', '\(userSession.unsafeJavascriptSessionUUID)');"))
                    return
                }

                if  let staticStorageHandler = self.staticStorageHandler,
                    let data = staticStorageHandler(userSession, httpRequest) {
                    self._beSendDataIfChanged(httpRequest, data)
                    return
                }

                userSession.beHandleRequest(self, httpRequest)
            }

            if let newJavascriptSessionUUID = javascriptSessionUUID,
               let oldJavascriptSessionUUID = httpRequest.sid,
               oldJavascriptSessionUUID != newJavascriptSessionUUID {
                if let userSession = userSessionManager.reassociate(cookieSessionUUID: cookieSessionUUID,
                                                                    oldJavascriptSessionUUID, newJavascriptSessionUUID) {
                    handleRequest(userSession)
                    return
                }
                return _beSendInternalError()
            }

            if let oldJavascriptSessionUUID = httpRequest.sid {
                if let userSession = userSessionManager.reassociate(cookieSessionUUID: cookieSessionUUID,
                                                                    oldJavascriptSessionUUID, oldJavascriptSessionUUID) {
                    handleRequest(userSession)
                    return
                }
                return _beSendInternalError()
            }

            // If no session uuid of any kind was supplied by the client, then this is technically an
            // error  (it should be served by the static handler if we don't have a client which is
            // running enough to provide us a session id).
            if let userSession = userSessionManager.get(cookieSessionUUID, javascriptSessionUUID) {
                handleRequest(userSession)
                return
            }

            return _beSendInternalError()

        } catch {
            socket.close()
        }
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
    public func beSendData(_ data: Data) -> Self {
        unsafeSend { self._beSendData(data) }
        return self
    }
    @discardableResult
    public func beSendDataIfChanged(_ httpRequest: HttpRequest,
                                    _ data: Data) -> Self {
        unsafeSend { self._beSendDataIfChanged(httpRequest, data) }
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
    public func beSendSuccess(_ message: String) -> Self {
        unsafeSend { self._beSendSuccess(message) }
        return self
    }
    @discardableResult
    public func beSendError(_ error: String) -> Self {
        unsafeSend { self._beSendError(error) }
        return self
    }
    @discardableResult
    public func beSendNotModified() -> Self {
        unsafeSend(_beSendNotModified)
        return self
    }

}
