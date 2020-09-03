import Foundation
import PicaroonFramework

let helloWorldResponse = HttpResponse.asData(nil, .ok, .txt, "Hello World")

class HelloWorld: UserSession {
    override func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
        connection.beSendInternalError()
    }
}

func handleStaticRequest(_ httpRequest: HttpRequest) -> Data? {
    return helloWorldResponse
}

Server<HelloWorld>("0.0.0.0", 8080, handleStaticRequest).run()
