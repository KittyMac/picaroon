import Flynn
import Foundation
import Hitch

public protocol AnyConnection {
    @discardableResult func beSend(httpResponse: HttpResponse) -> Self
    @discardableResult func beSendIfModified(httpRequest: HttpRequest,
                                             httpResponse: HttpResponse) -> Self
    @discardableResult func beEndUserSession() -> Self
    @discardableResult func beSendInternalError() -> Self
    @discardableResult func beSendUnauthorized() -> Self
    @discardableResult func beSendServiceUnavailable() -> Self
    @discardableResult func beSendResult(_ message: Hitch?) -> Self
    @discardableResult func beSendSuccess(_ message: Hitch) -> Self
    @discardableResult func beSendError(_ error: Hitch) -> Self
    
    @discardableResult func beSendResult(_ message: String?) -> Self
    @discardableResult func beSendSuccess(_ message: String) -> Self
    @discardableResult func beSendError(_ error: String) -> Self
    
    @discardableResult func beSendNotModified() -> Self
    
    func unsafeFileDescriptor() -> Int32
}

public class Connection: Actor, AnyConnection {
    
    // A dedicated thread which poll's all open sockets and, when those sockets can read, calls
    // checkForMoreData on the associated connection
    private class WatchSocket {
        let connection: Connection
        let socket: Socket
        var date: Date
        
        init(connection: Connection, socket: Socket, date: Date) {
            self.connection = connection
            self.socket = socket
            self.date = date
        }
        
        func shouldRead() -> Bool {
            guard connection.unsafeMessagesCount < 2 else { return false }
            // Wake the connection when it has data, and also periodically when it does not, so that
            // it gets a chance to enforce its client and server timeouts on idle sockets.
            if socket.poll() > 0 ||
                abs(date.timeIntervalSinceNow) > Connection.timeoutCheckInterval {
                date = Date()
                return true
            }
            return false
        }
    }
    
    /// How often an idle connection is woken to check its timeouts
    private static let timeoutCheckInterval: TimeInterval = 1.0
    private static let watchLock = NSLock()
    private static var watchSockets: [WatchSocket] = []
    private static var watchRunning = false
    
    private static func watch(connection: Connection,
                              socket: Socket) {
        watchLock.lock()
        if watchRunning == false {
            begin()
        }
        watchSockets.append(
            WatchSocket(connection: connection,
                        socket: socket,
                        date: Date())
        )
        watchLock.unlock()
    }
    
    private static func begin() {
        guard watchRunning == false else { return }
        watchRunning = true
        
        Thread {
            Flynn.threadSetName("Picaroon.Connection")
            while true {
                autoreleasepool {
                    watchLock.lock()
                    
                    var shouldSleep = true
                    watchSockets = watchSockets.filter({ watchSocket in
                        // if the socket is in error or is ready to read data
                        if watchSocket.shouldRead() {
                            watchSocket.connection.beCheckForMoreData()
                            shouldSleep = false
                        }
                        // if the socket has closed, drop our strong reference to the
                        // connection AND remove it from the ConnectionManager's active
                        // table. Both retainers must release or the connection (and its
                        // multi-megabyte buffer + file descriptor) leaks.
                        if watchSocket.socket.isClosed() {
                            ConnectionManager_CloseConnection(connection: watchSocket.connection)
                            return false
                        }
                        return true
                    })
                    watchLock.unlock()
                    
                    if shouldSleep {
                        Flynn.usleep(50_000)
                    }
                }
            }
        }.start()
    }
    
    
    // Handle a single TCP connection to a client. Multiple connections can link to the
    // same UserSession.

    private let socket: Socket
    public var unsafeClientAddress: String

    private var isProcessingRequest: Bool = false
    
    private var clientTimeout: TimeInterval = 5.0
    private var serverTimeout: TimeInterval = 30.0

    private var lastCommunicationTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    private var bufferSize = 1024 * 1024 * 2
    private var buffer: UnsafeMutablePointer<UInt8>
    private let endPtr: UnsafeMutablePointer<UInt8>
    private var currentPtr: UnsafeMutablePointer<UInt8>

    var unsafeUserSession: UserSession?
    private let userSessionManager: AnyUserSessionManager

    private let staticStorageHandler: StaticStorageHandler?
    
    private let config: ServerConfig

    private let connectionMaxBackoff: Double
    
    private var closeNextSend: Bool = false

    init(socket: Socket,
         clientAddress: String,
         config: ServerConfig,
         staticStorageHandler: StaticStorageHandler?,
         userSessionManager: AnyUserSessionManager) {
        self.socket = socket
        self.unsafeClientAddress = clientAddress
        self.userSessionManager = userSessionManager
        self.staticStorageHandler = staticStorageHandler
        self.config = config
        
        socket.setReadTimeout(milliseconds: 50)

        clientTimeout = config.clientTimeout
        serverTimeout = config.serverTimeout
        
        bufferSize = config.maxRequestInBytes
        connectionMaxBackoff = config.connectionMaxBackoff

        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize + 32)
        buffer.initialize(to: 0)

        currentPtr = buffer
        endPtr = buffer + bufferSize

        super.init()

        Connection.watch(connection: self,
                         socket: socket)
        
        beCheckForMoreData()
    }

    deinit {
        buffer.deallocate()
    }
    
    public func unsafeFileDescriptor() -> Int32 {
        return socket.fd()
    }
    
    // Close the underlying socket. Calling this lets the watch thread reap the
    // associated WatchSocket (which holds a strong reference to this Connection),
    // which is required for the Connection to be deallocated. Idempotent.
    public func unsafeCloseSocket() {
        socket.close()
    }
    
    internal func _beSend(httpResponse: HttpResponse) {
        httpResponse.send(config: config,
                          socket: socket,
                          userSession: unsafeUserSession)
        
        didSendResponse()
    }
    
    // The request in flight has been answered: idle time from here on is measured against
    // clientTimeout (waiting for the next request) rather than serverTimeout.
    private func didSendResponse() {
        isProcessingRequest = false
        lastCommunicationTime = ProcessInfo.processInfo.systemUptime
        
        if closeNextSend {
            socket.close()
        }
    }

    internal func _beSendIfModified(httpRequest: HttpRequest,
                                   httpResponse: HttpResponse) {
#if DEBUG
        _beSend(httpResponse: httpResponse)
#else
        if httpResponse.isNew(httpRequest) {
            httpResponse.send(config: config,
                              socket: socket,
                              userSession: unsafeUserSession)
            
            didSendResponse()
            
        } else {
            _beSendNotModified()
        }
#endif
    }

    internal func _beEndUserSession() {
        if let unsafeUserSession = unsafeUserSession {
            userSessionManager.end(unsafeUserSession)
        }
        unsafeUserSession = nil
    }

    internal func _beSendUnauthorized() {
        _beSend(httpResponse: HttpStaticResponse.unauthorized)
    }
    
    internal func _beSendInternalError() {
        _beSend(httpResponse: HttpStaticResponse.internalServerError)
    }
    
    internal func _beSendTooLargeError() {
        _beSend(httpResponse: HttpStaticResponse.requestTooLarge)
    }

    internal func _beSendServiceUnavailable() {
        _beSend(httpResponse: HttpStaticResponse.serviceUnavailable)
    }
    
    internal func _beSendResult(_ error: String?) {
        // combines beSendSuccess and beSendError in a single call
        guard let error = error else {
            return _beSend(httpResponse: HttpResponse(text: "success"))
        }
        _beSend(httpResponse: HttpResponse(status: .badRequest,
                                           type: .txt,
                                           payload: error))
    }
    
    internal func _beSendSuccess(_ message: String = "success") {
        _beSend(httpResponse: HttpResponse(text: message))
    }

    internal func _beSendError(_ error: String) {
        _beSend(httpResponse: HttpResponse(status: .badRequest,
                                           type: .txt,
                                           payload: error))
    }
    
    internal func _beSendResult(_ error: Hitch?) {
        // combines beSendSuccess and beSendError in a single call
        guard let error = error else {
            return _beSend(httpResponse: HttpResponse(text: "success"))
        }
        _beSend(httpResponse: HttpResponse(status: .badRequest,
                                           type: .txt,
                                           payload: error))
    }

    internal func _beSendSuccess(_ message: Hitch = "success") {
        _beSend(httpResponse: HttpResponse(text: message.halfhitch()))
    }

    internal func _beSendError(_ error: Hitch) {
        _beSend(httpResponse: HttpResponse(status: .badRequest,
                                           type: .txt,
                                           payload: error))
    }

    internal func _beSendNotModified() {
        _beSend(httpResponse: HttpStaticResponse.notModified)
    }
    
    internal func _beCheckForMoreData() {
        // Checks the socket to see if there is an HTTP command ready to be processed.
        // Whether we process one or not, we call beNextCommand() to check again in
        // the future for another command.
        if socket.isClosed() {
            if config.debug {
                fputs(" dropping already closed connection\n", stderr)
            }
            ConnectionManager_CloseConnection(connection: self)
            return
        }
        
        guard socket.poll() != 0 else {
            checkForTimeout()
            return
        }
        
        // Read some data onto the current buffer position
        let bytesRead = socket.recv(bytes: currentPtr,
                                    count: (endPtr - currentPtr))
        if bytesRead < 0 {
            if config.debug {
                fputs("Connection unexpectedly closed \(bytesRead)\n", stderr)
            }
            return
        }
        if bytesRead == 0 {
            checkForTimeout()
            return
        }

        lastCommunicationTime = ProcessInfo.processInfo.systemUptime

        currentPtr += bytesRead

        // if we're reading more data than our buffer allows, end the connection
        if currentPtr >= endPtr {
            if config.debug {
                fputs("Connection failed: incoming packet too large\n", stderr)
            }
            
            _beSendTooLargeError()
            ConnectionManager_CloseConnection(connection: self)
            return
        }

        // Reject requests which can never parse (unsupported method, malformed headers, unsupported
        // body framing). Without this they look identical to an incomplete request and we would
        // wait for more data forever.
        if let rejection = HttpRequest.validate(config: config,
                                                request: buffer,
                                                size: currentPtr - buffer) {
            if config.debug {
                fputs("Connection failed: rejecting malformed request (\(rejection.rawValue))\n", stderr)
            }
            
            closeNextSend = true
            currentPtr = buffer
            _beSend(httpResponse: Connection.rejection(for: rejection))
            ConnectionManager_CloseConnection(connection: self)
            return
        }

        // See if it is complete http request; if it is incomplete, we wait until we get more data
        guard let httpRequest = HttpRequest(config: config,
                                            request: buffer,
                                            size: currentPtr - buffer) else {
            if config.debug {
                fputs(" failed parsing packet of \(currentPtr - buffer) bytes; expect more data\n", stderr)
            }
            // We have an incomplete https request, wait for more data and try again
            self.unsafePriority = 99
            return
        }
        
        if config.debug,
           let desc = httpRequest.description {
            fputs("\(desc)\n", stderr)
        }
        
        if httpRequest.connection == "close" {
            closeNextSend = true
        }
        
        self.unsafeClientAddress = socket.clientAddress()
        
        self.isProcessingRequest = true
        self.unsafePriority = -1

        // reset current pointer to be read for the next http request
        currentPtr = buffer

        // First allow the static storage handler to handle it. It is the responsibility of the host site to
        // let reassociations (ie url param sid) to fall through and be handled by a user session. This is
        // critical because only the one call will have the sid reassociation parameter, and that one call
        // will need to ensure the return passes back the correct session UUIDs
        if  let staticStorageHandler = self.staticStorageHandler,
            let httpResponse = staticStorageHandler(self, config, httpRequest) {
            
            if config.debug {
                fputs("Connection request handled via static handler\n", stderr)
            }
            
            _beSendIfModified(httpRequest: httpRequest,
                              httpResponse: httpResponse)
            return
        }

        // Here's how we attempt to link sessions to web clients:
        // 1. Picaroon assigns a HTTP only cookieSessionUUID. These cookies are not accessible from javascript and
        //    provide the main linking of UserSession actor to the web session
        // 2. The client javascript can choose to send a "Session-Id" http header. Combined with the cookie
        //    this identifies the session at the window level (see UserSessionPer).
        // 3. The url may carry a token as "sid" in the url parameters: either an access token (lets a navigation
        //    such as a file download reach its session, see UserSession.unsafeIssueAccessToken) or a
        //    reassociation token. A reassociation token is issued by
        //    UserSession.unsafeAllowReassociation() (say, we're about to log in using a 3rd party service and
        //    that process will lose our http session cookie). It is single use, short lived, and unrelated to
        //    the session identifiers; redeeming it moves the session to this client and rotates both
        //    identifiers. Knowing a session's identifiers is never enough to move it.

        let cookieSessionUUID = httpRequest.cookies[config.sessionCookieName]
        let javascriptSessionUUID = httpRequest.sessionId?.hitch()

        if let sidToken = httpRequest.sid?.hitch() {
            if let userSession = userSessionManager.reassociate(reassociationToken: sidToken,
                                                                cookieSessionUUID: cookieSessionUUID) {
                self.unsafeUserSession = userSession
                
                if config.debug {
                    fputs("Connection request handled via user session reassociation\n", stderr)
                }
                
                userSession.beHandleRequest(connection: self,
                                            httpRequest: httpRequest)
                return
            }
            // An access token (see UserSession.unsafeIssueAccessToken) routes a navigation, such as a file
            // download, to the session which issued it, provided this request carries that session's cookie.
            if let userSession = userSessionManager.access(accessToken: sidToken,
                                                           cookieSessionUUID: cookieSessionUUID) {
                self.unsafeUserSession = userSession
                
                if config.debug {
                    fputs("Connection request handled via access token\n", stderr)
                }
                
                userSession.beHandleRequest(connection: self,
                                            httpRequest: httpRequest)
                return
            }
            
            // A used, expired or unknown token (ie the user refreshed the page they were returned to) is
            // not an error; carry on with the normal lookup. The sid value is never used as a session id.
            if config.debug {
                fputs("Connection sid token rejected\n", stderr)
            }
        }

        // If no session uuid of any kind was supplied by the client, then this is technically an
        // error  (it should be served by the static handler if we don't have a client which is
        // running enough to provide us a session id).
        if let userSession = userSessionManager.get(cookieSessionUUID, javascriptSessionUUID) {
            self.unsafeUserSession = userSession
            
            if config.debug {
                fputs("Connection request handled via user session\n", stderr)
            }
            
            userSession.beHandleRequest(connection: self,
                                        httpRequest: httpRequest)
            return
        }
        
        if config.debug {
            fputs("Connection failed: failed to attach sessionUUID to actor\n", stderr)
        }

        return _beSendInternalError()
    }
    
    private static func rejection(for status: HttpStatus) -> HttpResponse {
        switch status {
        case .notImplemented: return HttpStaticResponse.notImplemented
        case .requestTooLarge: return HttpStaticResponse.requestTooLarge
        default: return HttpStaticResponse.badRequest
        }
    }
    
    // Closes the connection if it has been idle for longer than allowed. While a request is being
    // handled the limit is serverTimeout; otherwise it is clientTimeout, which covers both a client
    // trickling in a partial request and an idle keep-alive connection.
    private func checkForTimeout() {
        let idle = ProcessInfo.processInfo.systemUptime - lastCommunicationTime
        
        if isProcessingRequest {
            guard idle > serverTimeout else { return }
            if config.debug {
                fputs("Connection failed: server timeout\n", stderr)
            }
            _beSendInternalError()
        } else {
            guard idle > clientTimeout else { return }
            if config.debug {
                fputs("Connection failed: client timeout\n", stderr)
            }
            // A partial request gets told why; an idle keep-alive connection is simply closed.
            if currentPtr > buffer {
                closeNextSend = true
                _beSend(httpResponse: HttpStaticResponse.requestTimeout)
            }
        }
        
        ConnectionManager_CloseConnection(connection: self)
    }
}
