import Flynn
import Foundation
import Socket

// swiftlint:disable function_body_length
// swiftlint:disable line_length

public protocol AnyConnection {
    @discardableResult func beSendData(_ data: Data) -> Self
    @discardableResult func beSendDataIfChanged(_ httpRequest: HttpRequest, _ data: Data) -> Self
    @discardableResult func beEndUserSession() -> Self
    @discardableResult func beSendInternalError() -> Self
    @discardableResult func beSendServiceUnavailable() -> Self
    @discardableResult func beSendSuccess() -> Self
    @discardableResult func beSendError(_ error: String) -> Self
    @discardableResult func beSendNotModified() -> Self
}

public class Connection: Actor, AnyConnection {
    // Handle a single TCP connection to a client. Multiple connections can link to the
    // same UserSession.

    private let socket: Socket

#if DEBUG
    private let timeout: TimeInterval = 5.0
#else
    private let timeout: TimeInterval = 20.0
#endif
    private var lastCommunicationTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    private let bufferSize = 16384
    private var buffer: UnsafeMutablePointer<CChar>
    private let endPtr: UnsafeMutablePointer<CChar>
    private var currentPtr: UnsafeMutablePointer<CChar>

    private var userSession: UserSession?
    private let userSessionManager: AnyUserSessionManager

    private let staticStorageHandler: StaticStorageHandler?

    private var checkForMoreDataScheduled = false

    init(_ socket: Socket,
         _ staticStorageHandler: StaticStorageHandler?,
         _ userSessionManager: AnyUserSessionManager) {
        self.socket = socket
        self.userSessionManager = userSessionManager
        self.staticStorageHandler = staticStorageHandler

        try? socket.setReadTimeout(value: 5)

        buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
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
            userSessionManager.end(userSession.unsafeSessionUUID)
        }
        userSession = nil
    }

    private func _beSendInternalError() {
        _beSendData(HttpResponse.asData(userSession, .internalServerError, .txt))
    }

    private func _beSendServiceUnavailable() {
        _beSendData(HttpResponse.asData(userSession, .serviceUnavailable, .txt))
    }

    private func _beSendSuccess() {
        _beSendData(HttpResponse.asData(userSession, .ok, .txt, "success"))
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
            let httpRequest = HttpRequest(buffer, currentPtr - buffer + 1)

            // We have a complete http request, we need to process it
            if httpRequest.incomplete {
                checkForMoreDataIfNeeded()
                return
            }

            //if let requestString = String(bytesNoCopy: buffer, length: currentPtr - buffer + 1, encoding: .utf8, freeWhenDone: false) {
            //    print(requestString)
            //}

            // reset current pointer to be read for the next http request
            currentPtr = buffer

            // check to see if this is handled by the static storage handler
            if  let staticStorageHandler = staticStorageHandler,
                let data = staticStorageHandler(httpRequest) {
                _beSendDataIfChanged(httpRequest, data)
                return
            }

            // Handle requests for static resources
            // Before we give any resources to the client, we need to assign a user session to this connection
            let sessionToken = httpRequest.cookies[Picaroon.userSessionCookie]
            var shouldGenerateNewSession = false

            if userSession == nil {
                shouldGenerateNewSession = true
            }
            if  let userSession = userSession,
                let sessionToken = sessionToken,
                userSession.unsafeSessionUUID != sessionToken {
                shouldGenerateNewSession = true
            }

            if shouldGenerateNewSession {
                //print("retrieving user session for: \(sessionToken)")
                userSession = userSessionManager.get(sessionToken)
            }

            if let userSession = userSession {
                userSession.beHandleRequest(self, httpRequest)
            } else {
                _beSendInternalError()
            }

        } catch {
            socket.close()
        }
    }
}

// MARK: - Autogenerated by FlynnLint
// Contents of file after this marker will be overwritten as needed

extension Connection {

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
    public func beSendSuccess() -> Self {
        unsafeSend(_beSendSuccess)
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
