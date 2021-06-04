import Foundation
import Flynn
import Socket

public typealias StaticStorageHandler = (HttpRequest) -> Data?

public struct ServerConfig: Codable {
    let address: String
    let port: Int
    let maxRequestInBytes: Int

    public init(address: String,
                port: Int,
                maxRequestInBytes: Int = 1024 * 1024 * 8) {
        self.address = address
        self.port = port
        self.maxRequestInBytes = maxRequestInBytes
    }
}

public class Server<T: UserSession> {
    // A server which listens on an address and a port

    public let config: ServerConfig

    private var listening = false

    private var userSessionManager = UserSessionManager<T>()
    public var staticStorageHandler: StaticStorageHandler?

    public init(config: ServerConfig,
                staticStorageHandler: StaticStorageHandler? = nil) {
        self.config = config
        self.staticStorageHandler = staticStorageHandler
    }

    @discardableResult
    private func loop() -> Bool {
        do {
            let serverSocket = try Socket.create()
            try serverSocket.listen(on: config.port, node: config.address)

            repeat {
#if os(Linux)
                if let newSocket = try? serverSocket.acceptClientConnection() {
                    _ = Connection(socket: newSocket,
                                   config: config,
                                   staticStorageHandler: staticStorageHandler,
                                   userSessionManager: userSessionManager)
                }
#else
                autoreleasepool {
                    if let newSocket = try? serverSocket.acceptClientConnection() {
                        _ = Connection(socket: newSocket,
                                       config: config,
                                       staticStorageHandler: self.staticStorageHandler,
                                       userSessionManager: self.userSessionManager)
                    }
                }
#endif
            } while self.listening

        } catch {
            print("socket error: \(error)")
            return false
        }
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
}
