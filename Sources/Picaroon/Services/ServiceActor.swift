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
    open func safeHandleRequest(userSession: UserServiceableSession,
                                jsonElement: JsonElement,
                                httpRequest: HttpRequest,
                                _ returnCallback: @escaping (JsonElement?, HttpResponse?) -> ()) {
        returnCallback(JsonElement(unknown: [
            "error": "service actor not properly configured"
        ]), HttpStaticResponse.internalServerError)
    }
    
    private func _beHandleRequest(userSession: UserServiceableSession,
                                  jsonElement: JsonElement,
                                  httpRequest: HttpRequest,
                                  _ returnCallback: @escaping (JsonElement?, HttpResponse?) -> ()) {
        safeHandleRequest(userSession: userSession,
                          jsonElement: jsonElement,
                          httpRequest: httpRequest,
                          returnCallback)
    }
    
    /// Overridden by subclass to handle requests
    open func safeHandleShutdown(_ returnCallback: @escaping () -> ()) {
        returnCallback()
    }
    
    private func _beHandleShutdown(_ returnCallback: @escaping () -> ()) {
        safeHandleShutdown(returnCallback)
    }
}

// MARK: - Autogenerated by FlynnLint
// Contents of file after this marker will be overwritten as needed

extension ServiceActor {

    @discardableResult
    public func beHandleRequest(userSession: UserServiceableSession,
                                jsonElement: JsonElement,
                                httpRequest: HttpRequest,
                                _ sender: Actor,
                                _ callback: @escaping ((JsonElement?, HttpResponse?) -> Void)) -> Self {
        unsafeSend {
            self._beHandleRequest(userSession: userSession, jsonElement: jsonElement, httpRequest: httpRequest) { arg0, arg1 in
                sender.unsafeSend {
                    callback(arg0, arg1)
                }
            }
        }
        return self
    }
    @discardableResult
    public func beHandleShutdown(_ sender: Actor,
                                 _ callback: @escaping (() -> Void)) -> Self {
        unsafeSend {
            self._beHandleShutdown() { 
                sender.unsafeSend {
                    callback()
                }
            }
        }
        return self
    }

}