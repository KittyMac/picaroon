import Flynn
import Foundation
import Hitch
import Spanker

/// A service is an actor which generically provides additional functionality to a
/// UserServiceableSession.
open class ServiceActor: Actor {
    
    private let serviceName: Hitch
    
    override public init() {
        serviceName = Hitch(string: String(describing: Self.self))
    }
    
    /// Overridden by subclass to use custom service name
    open var unsafeServiceName: Hitch {
        return serviceName
    }
    
    /// Overridden by subclass to handle requests
    open func safeHandleRequest(jsonElement: JsonElement,
                                httpRequest: HttpRequest,
                                _ returnCallback: (HttpResponse) -> ()) {
        returnCallback(HttpStaticResponse.internalServerError)
    }    
    
    private func _beHandleRequest(jsonElement: JsonElement,
                                  httpRequest: HttpRequest,
                                  _ returnCallback: (HttpResponse) -> ()) {
        safeHandleRequest(jsonElement: jsonElement,
                          httpRequest: httpRequest,
                          returnCallback)
    }
}

// MARK: - Autogenerated by FlynnLint
// Contents of file after this marker will be overwritten as needed

extension ServiceActor {

    @discardableResult
    public func beHandleRequest(jsonElement: JsonElement,
                                httpRequest: HttpRequest,
                                _ sender: Actor,
                                _ callback: @escaping ((HttpResponse) -> Void)) -> Self {
        unsafeSend {
            self._beHandleRequest(jsonElement: jsonElement, httpRequest: httpRequest) { arg0 in
                sender.unsafeSend {
                    callback(arg0)
                }
            }
        }
        return self
    }

}
