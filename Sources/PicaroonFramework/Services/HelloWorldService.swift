import Flynn
import Foundation
import Socket
import Hitch
import Spanker

/// A simple example service
open class HelloWorldService: ServiceActor {
    private let response = JsonElement(unknown: "Hello World!")
            
    override func safeHandleRequest(jsonElement: JsonElement,
                                    httpRequest: HttpRequest,
                                    _ returnCallback: (JsonElement) -> ()) {
        returnCallback(response)
    }
}
