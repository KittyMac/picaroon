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
                <script>
                    function uuidv4() {
                        return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, c =>
                            (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)
                        );
                    }

                    if (sessionStorage.getItem("Session-Id") == undefined) {
                        sessionStorage.setItem("Session-Id", uuidv4())
                    }
                </script>
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

let config = ServerConfig(address: "0.0.0.0",
                          port: 8080,
                          maxRequestInBytes: 1024 * 1024 * 8)

Server<HelloWorld>(config: config,
                   staticStorageHandler: handleStaticRequest).run()
