import Foundation
import Flynn

public typealias StaticStorageHandler = (HttpRequest) -> HttpResponse?

public enum UserSessionPer: Int, Codable {
    case window = 0
    case browser = 1
}

public struct ServerConfig: Codable {
    let address: String
    let port: Int

    let requestTimeout: TimeInterval
    let maxRequestInBytes: Int

    let sessionPer: UserSessionPer

    public init(address: String,
                port: Int,
                sessionPer: UserSessionPer = .window,
                requestTimeout: TimeInterval = 30.0,
                maxRequestInBytes: Int = 1024 * 1024 * 8) {
        self.address = address
        self.port = port
        self.sessionPer = sessionPer
        self.requestTimeout = requestTimeout
        self.maxRequestInBytes = maxRequestInBytes
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
