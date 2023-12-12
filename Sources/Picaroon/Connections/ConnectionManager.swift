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
        active[connection.unsafeUUID] = nil
    }
    
    internal func _beClose(session: UserSession) {
        for connection in active.values where connection.unsafeUserSession == session {
            active[connection.unsafeUUID] = nil
        }
    }
}
