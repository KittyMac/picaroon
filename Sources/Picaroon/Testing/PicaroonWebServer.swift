import Foundation
import Hitch
import Flynn

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

fileprivate let data = Data(repeating: 55, count: 1024*1024*1024)

private func handleStaticRequest(connection: Connection,
                                 config: ServerConfig,
                                 httpRequest: HttpRequest) -> HttpResponse? {
    // http://127.0.0.1:8080/data
    
    if httpRequest.method == .GET && httpRequest.url == "/data" {
        return HttpResponse(status: .ok, type: .bin, payload: data)
    }
    
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
                                    HttpResponse(javascript: "sessionStorage.setItem('Session-Id', '{0}');" << [unsafeJavascriptSessionUUID])
                )
                return
            }

            connection.beSend(httpResponse: HttpResponse(text: HalfHitch(string: unsafeUUID)))
        }
    }

    public class WebServer<T:UserSession> {
        let config: ServerConfig
        let server: Server<T>
        public init(port: Int, basePath: String = "/") {
            config = ServerConfig(address: "0.0.0.0",
                                  port: port,
                                  basePath: basePath)

            server = Server<T>(config: config,
                               staticStorageHandler: handleStaticRequest)
            server.listen()

            Flynn.sleep(1)
        }

        public func numberOfUserSessions() -> Int {
            return server.numberOfUserSessions()
        }
    }
}
