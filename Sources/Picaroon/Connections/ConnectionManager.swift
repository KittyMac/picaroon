import Flynn
import Foundation
import Hitch

fileprivate let lock = NSLock()
fileprivate var activeConnections: [String: Connection] = [:]

func ConnectionManager_OpenConnection(socket: Socket,
                                      clientAddress: String,
                                      config: ServerConfig,
                                      staticStorageHandler: StaticStorageHandler?,
                                      userSessionManager: AnyUserSessionManager) {
    let connection = Connection(socket: socket,
                                clientAddress: clientAddress,
                                config: config,
                                staticStorageHandler: staticStorageHandler,
                                userSessionManager: userSessionManager)
    
    lock.lock()
    activeConnections[connection.unsafeUUID] = connection
    lock.unlock()
}

internal func ConnectionManager_CloseConnection(connection: Connection) {
    // Close the socket as well as dropping it from the active table. Otherwise
    // server-initiated closes (timeout, request-too-large) remove the connection
    // here but leave the socket open, so the watch thread never reaps the
    // WatchSocket and the connection (2MB buffer + fd) leaks until/unless the
    // client happens to close the TCP connection.
    connection.unsafeCloseSocket()
    
    lock.lock()
    activeConnections[connection.unsafeUUID] = nil
    lock.unlock()
}

internal func ConnectionManager_CloseConnection(session: UserSession) {
    lock.lock()
    let localConnections = activeConnections.values
    lock.unlock()
    
    for connection in localConnections where connection.unsafeUserSession == session {
        connection.unsafeCloseSocket()
        
        lock.lock()
        activeConnections[connection.unsafeUUID] = nil
        lock.unlock()
    }
}
