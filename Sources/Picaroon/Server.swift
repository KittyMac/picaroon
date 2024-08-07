import Foundation
import Flynn
import Hitch

#if os(Linux) || os(Android) || os(Windows)
public func autoreleasepool(_ block: @escaping () -> ()) {
    block()
}
#endif

public typealias StaticStorageHandler = (Connection, ServerConfig, HttpRequest) -> HttpResponse?

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
    public let address: Hitch
    public let port: Int

    public let basePath: Hitch
    
    public let clientTimeout: TimeInterval
    public let serverTimeout: TimeInterval
    
    public let maxRequestInBytes: Int
    public let connectionMaxBackoff: Double

    public let sessionPer: UserSessionPer
    public let sessionActivityTimeout: TimeInterval
    public let maximumSessions: Int
    
    public let debug: Bool

    public init(address: String,
                port: Int,
                basePath: String = "/",
                sessionPer: UserSessionPer = .window,
                sessionActivityTimeout: TimeInterval = 60 * 60,
                maximumSessions: Int = 1_000_000,
                clientTimeout: TimeInterval = 5.0,
                serverTimeout: TimeInterval = 30.0,
                maxRequestInBytes: Int = 1024 * 1024 * 8,
                connectionMaxBackoff: Double = 0.5,
                debug: Bool = false) {
        self.address = Hitch(string: address)
        self.port = port
        self.sessionPer = sessionPer
        self.sessionActivityTimeout = sessionActivityTimeout
        self.maximumSessions = maximumSessions
        self.clientTimeout = clientTimeout
        self.serverTimeout = serverTimeout
        self.maxRequestInBytes = maxRequestInBytes
        self.connectionMaxBackoff = connectionMaxBackoff
        self.debug = debug
        self.basePath = Hitch(string: basePath)
        
        if self.basePath.ends(with: "/") {
            self.basePath.count = self.basePath.count - 1
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
        if config.debug {
            fputs("listen on \(config.address.description) \(config.port)\n", stderr)
        }
        serverSocket.listen(address: config.address.description,
                            port: config.port)

        repeat {
            autoreleasepool {
                var clientAddress = ""
                if self.config.debug {
                    fputs("accept on \(self.config.address.description) \(self.config.port)\n", stderr)
                }
                if let newSocket = serverSocket.accept(blocking: true, clientAddress: &clientAddress) {
                    if self.config.debug {
                        fputs("read on \(self.config.address.description) \(self.config.port)\n", stderr)
                    }
                    ConnectionManager.shared.beOpen(socket: newSocket,
                                                    clientAddress: clientAddress,
                                                    config: self.config,
                                                    staticStorageHandler: self.staticStorageHandler,
                                                    userSessionManager: self.userSessionManager)
                }
            }
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
        Thread {
            Flynn.threadSetName("Picaroon.Server")
            self.loop()
        }.start()
    }

    public func stop() {
        listening = false
    }

    public func numberOfUserSessions() -> Int {
        return userSessionManager.numberOfUserSessions()
    }
}
