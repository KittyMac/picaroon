import Foundation
import PicaroonFramework

let helloWorldResponse = HttpResponse.asData(nil, .ok, .txt, "Hello World")

class HelloWorld: UserSession {
    override func safeHandleRequest(connection: AnyConnection,
                                    httpRequest: HttpRequest) {
        connection.beSendInternalError()
    }
}

func handleStaticRequest(_ httpRequest: HttpRequest) -> Data? {
    return helloWorldResponse
}

Server<HelloWorld>(config: ServerConfig(address: "0.0.0.0", port: 8080),
                   staticStorageHandler: handleStaticRequest).run()
