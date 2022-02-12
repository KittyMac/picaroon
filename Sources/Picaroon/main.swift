import Foundation
import PicaroonFramework

let helloWorldResponse = HttpResponse(text: "Hello World")

class HelloWorld: UserSession {
    override func safeHandleRequest(connection: AnyConnection,
                                    httpRequest: HttpRequest) {
        connection.beSendInternalError()
    }
}

func handleStaticRequest(_ httpRequest: HttpRequest) -> HttpResponse? {
    return helloWorldResponse
}

Server<HelloWorld>(config: ServerConfig(address: "0.0.0.0", port: 8080),
                   staticStorageHandler: handleStaticRequest).run()
