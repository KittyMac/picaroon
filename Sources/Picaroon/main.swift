import Foundation
import PicaroonFramework

struct APIRequest {
    let type: String
}

class HelloWorld: UserSession {
    override func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
        if let content = httpRequest.content,
            let contentString = String(data: content, encoding: .utf8),
            contentString == "HelloWorld" {
            connection.beSendData(HttpResponse.asData(nil, .ok, .txt, "Hello to you, \(unsafeSessionUUID)"))
            return
        }
        connection.beSendInternalError()
    }
}

func handleStaticRequest(_ httpRequest: HttpRequest) -> Data? {
    guard httpRequest.sessionId == nil else { return nil }

    if httpRequest.url == "/" {
        return HttpResponse.asData(nil, .ok, .html, """
        <html>
            <head>
                <script src="session.js"></script>
            </head>
            <body>
                <script>
                    alert("Session-Id: " + sessionStorage.getItem("Session-Id"))

                    function callAPI() {
                        var xhttp = new XMLHttpRequest();
                        xhttp.onreadystatechange = function() {
                            if (this.readyState == 4) {
                                alert(this.responseText);
                            }
                        };
                        xhttp.open("POST", "/");
                        xhttp.setRequestHeader("Session-Id", sessionStorage.getItem("Session-Id"));
                        xhttp.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");
                        xhttp.send("HelloWorld");
                    }
                </script>
                <button type="button" onclick="callAPI()">Send API Call!</button>
            </body>
        </html>
        """)
    }

    return nil
}

Server<HelloWorld>("0.0.0.0", 8080, handleStaticRequest).run()
