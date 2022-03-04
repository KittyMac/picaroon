import Foundation
import Flynn

public typealias StaticStorageHandler = (HttpRequest) -> HttpResponse?

/// Three different mechanisms for allowing session persistance, in order from most complicated to
/// least complicated.
///
/// window:     a two UUID system which uses one http-only cookie UUID and a separate
///         Session-Id http header. The cookie uuid "painlessly" persists a session
///         to the browser level, however is the same across all windows. Session-Id is
///         expected to be received, stored in session storage, and sent back with future requests.
///         This allows granularity at the window level. The combination of the two then provides
///         the full, unique session UUID.
///
/// browser:    same as window above but it only uses the http-only cookie UUID.
///
/// api:            same as window above, but only uses Session-Id passes along in the http headers.
///
public enum UserSessionPer: Int, Codable {
    case window = 0
    case browser = 1
    case api = 2
}

public struct ServerConfig: Codable {
    let address: String
    let port: Int

    let basePath: String
    
    let requestTimeout: TimeInterval
    let maxRequestInBytes: Int

    let sessionPer: UserSessionPer

    public init(address: String,
                port: Int,
                basePath: String = "/",
                sessionPer: UserSessionPer = .window,
                requestTimeout: TimeInterval = 30.0,
                maxRequestInBytes: Int = 1024 * 1024 * 8) {
        self.address = address
        self.port = port
        self.sessionPer = sessionPer
        self.requestTimeout = requestTimeout
        self.maxRequestInBytes = maxRequestInBytes
        
        if basePath.hasSuffix("/") {
            self.basePath = String(basePath.dropLast())
        } else {
            self.basePath = basePath
        }
    }
}

public class Server<T: UserSession> {
    // A server which listens on an address and a port

    public let config: ServerConfig

    private var listening = false

    private var userSessionManager: UserSessionManager<T>
    public var staticStorageHandler: StaticStorageHandler?

    public init(config: ServerConfig,
                staticStorageHandler: StaticStorageHandler? = nil) {
        self.config = config
        self.staticStorageHandler = staticStorageHandler
        self.userSessionManager = UserSessionManager<T>(config: config)
    }

    @discardableResult
    private func loop() -> Bool {
        guard let serverSocket = Socket(blocking: true) else { return false }
        
        serverSocket.listen(address: config.address,
                            port: config.port)

        repeat {
#if os(Linux)
            if let newSocket = serverSocket.accept(blocking: true) {
                _ = Connection(socket: newSocket,
                               config: config,
                               staticStorageHandler: staticStorageHandler,
                               userSessionManager: userSessionManager)
            }
#else
            autoreleasepool {
                if let newSocket = serverSocket.accept(blocking: true) {
                    _ = Connection(socket: newSocket,
                                   config: config,
                                   staticStorageHandler: self.staticStorageHandler,
                                   userSessionManager: self.userSessionManager)
                }
            }
#endif
        } while self.listening
        return true
    }

    @discardableResult
    public func run() -> Bool {
        // run the server synchronously
        guard !listening else { return false }
        listening = true
        return loop()
    }

    public func listen() {
        // run the server asynchronously
        guard !listening else { return }

        listening = true
        DispatchQueue.global(qos: .background).async {
            self.loop()
        }
    }

    public func stop() {
        listening = false
    }

    public func numberOfUserSessions() -> Int {
        return userSessionManager.numberOfUserSessions()
    }
}
