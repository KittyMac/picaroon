// flynn:ignore Access Level Violation

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
        returnCallback(^[
            "error": "service actor not properly configured"
        ], HttpStaticResponse.internalServerError)
    }
    
    internal func _beHandleRequest(userSession: UserServiceableSession,
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
    
    internal func _beHandleShutdown(_ returnCallback: @escaping () -> ()) {
        safeHandleShutdown(returnCallback)
    }
}
