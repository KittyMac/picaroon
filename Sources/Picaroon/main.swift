import PicaroonFramework
import Foundation

class HelloWorld: UserSession {
    override func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
        connection.beSendData(HttpResponse.asData(self, .ok, .txt, "Hello World"))
    }
}

Server<HelloWorld>("0.0.0.0", 8080).run()
