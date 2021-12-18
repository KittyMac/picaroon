import XCTest
@testable import PicaroonFramework

private func handleStaticRequest(_ httpRequest: HttpRequest) -> Data? {
    return nil
}

class WebUserSession: UserSession {
    override func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
        if let content = httpRequest.content,
           let contentString = String(data: content, encoding: .utf8),
           contentString.contains("Server_AllowReassociation") {
            beAllowReassociation()
        }
        let data = HttpResponse.asData(self, .ok, .txt, unsafeUUID)
        connection.beSendData(data)
    }
}

class WebServer {
    let config: ServerConfig
    let server: Server<WebUserSession>
    init(port: Int) {
        config = ServerConfig(address: "0.0.0.0", port: port)
        
        server = Server<WebUserSession>(config: config,
                                        staticStorageHandler: handleStaticRequest)
        server.listen()
        
        sleep(1)
    }
    
    public func numberOfUserSessions() -> Int {
        return server.numberOfUserSessions()
    }
}
