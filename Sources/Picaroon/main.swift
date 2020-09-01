import PicaroonFramework
import FlynnHttp
import Foundation

class HelloWorld: Picaroon.UserSession {
    override func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
        connection.beSendData(HttpResponse.asData(self, .ok, .txt, "Hello World"))
    }
}

Picaroon.Server<HelloWorld>("0.0.0.0", 8080).listen()
