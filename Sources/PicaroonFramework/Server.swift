import Foundation
import Flynn
import Socket

extension Picaroon {
    public class Server<T: UserSession> {
        // A server which listens on an address and a port

        public let address: String
        public let port: Int

        private var listening = false

        private var userSessionManager = UserSessionManager<T>()

        public init(_ address: String,
                    _ port: Int) {
            self.address = address
            self.port = port
        }

        public func listen() {
            guard !listening else { return }

            listening = true
            DispatchQueue.global(qos: .background).async {
                do {
                    let serverSocket = try Socket.create()
                    try serverSocket.listen(on: self.port, node: self.address)

                    repeat {
#if os(Linux)
                        if let newSocket = try? serverSocket.acceptClientConnection() {
                            _ = Connection(newSocket, userSessionManager)
                        }
#else
                        autoreleasepool {
                            if let newSocket = try? serverSocket.acceptClientConnection() {
                                _ = Connection(newSocket, self.userSessionManager)
                            }
                        }
#endif
                    } while self.listening

                } catch {
                    print("socket error: \(error)")
                }
            }
        }

        public func stop() {
            listening = false
        }
    }
}
