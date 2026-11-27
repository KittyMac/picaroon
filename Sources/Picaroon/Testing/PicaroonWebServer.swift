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
            // ajax: allow reassociation, hand the single-use token back to the page
            if let content = httpRequest.content,
               content.contains("Server_AllowReassociation") {
                guard let token = unsafeAllowReassociation() else {
                    connection.beSendInternalError()
                    return
                }
                connection.beSend(httpResponse: HttpResponse(text: token))
                return
            }

            // ajax: issue an access token so the page can navigate to a download
            if let content = httpRequest.content,
               content.contains("Server_IssueAccessToken") {
                let singleUse = content.contains("singleUse")
                guard let token = unsafeIssueAccessToken(singleUse: singleUse) else {
                    connection.beSendInternalError()
                    return
                }
                connection.beSend(httpResponse: HttpResponse(text: token))
                return
            }

            // navigation to a "download": report which server side actor served it
            if httpRequest.method == .GET,
               let url = httpRequest.url,
               url.starts(with: "/download") {
                connection.beSend(httpResponse: HttpResponse(text: HalfHitch(string: unsafeUUID)))
                return
            }

            // page load. A navigation cannot carry the Session-Id header, so in .window mode this request
            // is handled by a throwaway session; the tab's real identity is whatever it already holds in
            // session storage, so only fill an empty slot. A return with ?sid=<token> is different: the
            // reassociation rotated the identifiers, so the page must overwrite (and should then strip sid
            // from its url with history.replaceState, so a refresh does not repeat this).
            if httpRequest.method == .GET {
                if httpRequest.sid != nil {
                    connection.beSend(httpResponse:
                                        HttpResponse(javascript: "sessionStorage.setItem('Session-Id', '{0}');" << [unsafeJavascriptSessionUUID])
                    )
                } else {
                    connection.beSend(httpResponse:
                                        HttpResponse(javascript: "if (!sessionStorage.getItem('Session-Id')) sessionStorage.setItem('Session-Id', '{0}');" << [unsafeJavascriptSessionUUID])
                    )
                }
                return
            }

            // ajax: report which server side actor handled us
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
