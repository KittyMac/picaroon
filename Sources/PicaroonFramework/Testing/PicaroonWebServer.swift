import Foundation
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func handleStaticRequest(_ httpRequest: HttpRequest) -> HttpResponse? {
    if httpRequest.url?[0] == .forwardSlash {
        return nil
    }
    if httpRequest.method == .GET {
        return HttpResponse(text: "static resource")
    }
    return nil
}

extension PicaroonTesting {
    open class WebUserSession: UserSession {
        open override func safeHandleRequest(connection: AnyConnection,
                                             httpRequest: HttpRequest) {
            if let content = httpRequest.content,
               content.contains("Server_AllowReassociation") {
                beAllowReassociation()
            }

            if httpRequest.url?[0] == .forwardSlash || httpRequest.urlParameters?.contains("sid=") == true {
                connection.beSend(httpResponse:
                    HttpResponse(javascript: Hitch("sessionStorage.setItem('Session-Id', '{0}');", unsafeJavascriptSessionUUID))
                )
                return
            }

            connection.beSend(httpResponse: HttpResponse(text: Hitch(string: unsafeUUID)))
        }
    }

    public class WebServer<T:UserSession> {
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
