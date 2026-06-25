import Flynn
import Foundation
import Hitch

public class ConnectionManager: Actor {
    public static let shared = ConnectionManager()
    private override init() {
        super.init()
        unsafePriority = 1
    }
    
    private var active: [String: Connection] = [:]
    
    // Number of connections currently held in the active table. Useful for
    // monitoring and for asserting that connections are released after close.
    public func unsafeNumberOfActiveConnections() -> Int {
        return active.count
    }
    
    internal func _beOpen(socket: Socket,
                          clientAddress: String,
                          config: ServerConfig,
                          staticStorageHandler: StaticStorageHandler?,
                          userSessionManager: AnyUserSessionManager) {
        let connection = Connection(socket: socket,
                                    clientAddress: clientAddress,
                                    config: config,
                                    staticStorageHandler: staticStorageHandler,
                                    userSessionManager: userSessionManager)
        
        active[connection.unsafeUUID] = connection
    }
    
    internal func _beClose(connection: Connection) {
        // Close the socket as well as dropping it from the active table. Otherwise
        // server-initiated closes (timeout, request-too-large) remove the connection
        // here but leave the socket open, so the watch thread never reaps the
        // WatchSocket and the connection (2MB buffer + fd) leaks until/unless the
        // client happens to close the TCP connection.
        connection.unsafeCloseSocket()
        active[connection.unsafeUUID] = nil
    }
    
    internal func _beClose(session: UserSession) {
        for connection in active.values where connection.unsafeUserSession == session {
            connection.unsafeCloseSocket()
            active[connection.unsafeUUID] = nil
        }
    }
}
