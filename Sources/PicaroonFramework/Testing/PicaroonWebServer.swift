import Foundation

private func handleStaticRequest(_ httpRequest: HttpRequest) -> Data? {
    if httpRequest.url == "/" {
        return nil
    }
    if httpRequest.method == .GET {
        return HttpResponse.asData(nil, .ok, .txt, "static resource")
    }
    return nil
}

public extension PicaroonTesting {
    open class WebUserSession: UserSession {
        public override func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
            if let content = httpRequest.content,
               let contentString = String(data: content, encoding: .utf8),
               contentString.contains("Server_AllowReassociation") {
                beAllowReassociation()
            }

            if httpRequest.url == "/" || httpRequest.urlParameters?.contains("sid=") == true {
                let data = HttpResponse.asData(self, .ok, .js, "sessionStorage.setItem('Session-Id', '\(unsafeJavascriptSessionUUID)');")
                connection.beSendData(data)
                return
            }

            let data = HttpResponse.asData(self, .ok, .txt, unsafeUUID)
            connection.beSendData(data)
        }
    }

    class WebServer<T:UserSession> {
        let config: ServerConfig
        let server: Server<T>
        public init(port: Int) {
            config = ServerConfig(address: "0.0.0.0", port: port)

            server = Server<T>(config: config,
                               staticStorageHandler: handleStaticRequest)
            server.listen()

            sleep(1)
        }

        public func numberOfUserSessions() -> Int {
            return server.numberOfUserSessions()
        }
    }
}
