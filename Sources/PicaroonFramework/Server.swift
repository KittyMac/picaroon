import Foundation
import Flynn
import FlynnHttp
import Socket

extension Picaroon {
    public struct Server<T: UserSession> {
        // A server which listens on an address and a port

        public let address: String
        public let port: Int

        private var userSessionManager = UserSessionManager<T>()

        public init(_ address: String,
                    _ port: Int) {
            self.address = address
            self.port = port
        }

        public func listen() {
            do {
                let serverSocket = try Socket.create()
                try serverSocket.listen(on: port, node: address)

                repeat {
    #if os(Linux)
                    if let newSocket = try? serverSocket.acceptClientConnection() {
                        _ = Connection(newSocket, userSessionManager)
                    }
    #else
                    autoreleasepool {
                        if let newSocket = try? serverSocket.acceptClientConnection() {
                            _ = Connection(newSocket, userSessionManager)
                        }
                    }
    #endif
                } while true

            } catch {
                print("socket error: \(error)")
            }
        }
    }
}
