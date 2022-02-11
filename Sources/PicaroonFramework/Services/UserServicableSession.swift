import Flynn
import Foundation
import Hitch
import Sextant
import Spanker

public typealias ServiceResultCallback = (Bool) -> Void

/// A type of UserSession which allows generic services to be attached to it.
/// Services work thusly:
/// * Services work entirely upon the JSON uploaded in the HTTP content
/// * Services are uniquely identifiable by their name
/// * Only one of each type of service can be attached to a user session at a time
/// * As only one type of service can be attached to a session, only one service may
///     may response to any one request
///
/// Example usage:
/// Let's suppose that our application has both normal users and admin users. Admin
/// users have access to additional APIs which normal users do not. As such, when an
/// admin user is successfully authenticated, we can simply attach the "AdminUserService"
/// to the UserServicableSession. All requests to the admin service to admin service can
/// now be fulfilled (for a non-admin, these request will fail to match a service and will
/// will result in error. For the authenticated admin user, it will match the service
/// and process normally).
///
/// Note: The name of the service is name of the class as returned by
/// String(describing: type(of: service))
open class UserServicableSession: UserSession {
    private var services = [HalfHitch: ServiceActor]()
    
    private func _beAdd(service: ServiceActor) {
        self.services[service.unsafeServiceName.halfhitch()] = service
    }
    
    private func _beRemove(service: ServiceActor) {
        self.services.removeValue(forKey: service.unsafeServiceName.halfhitch())
    }
    
    open override func safeHandleRequest(connection: AnyConnection,
                                         httpRequest: HttpRequest) {
        guard let json = httpRequest.json else {
            connection.beSendInternalError()
            return
        }
        
        // Input: We allow sending an array of service commands
        // [{"service":"HelloWorldService"},{"service":"AdminUserService","command":"DeleteUser"}]
        
        // Output: We expect an array of results
        // [{"service":"HelloWorldService", "result":"Hello World"}, {"service":"AdminUserService","error":"500"}]
        let results = JsonElement(unknown: [])
        var servicesCalled = 0
        var servicesFinished = 0
        
        
        // TODO: We cannot do it this way because the memory backing the service
        // jsonElement is only garaunteed for the life of the .query() call.
        // We can work through a loophole if content were a hitch, then we can
        // garauntee it be around for the life of the hitch (which could be tied
        // to the life of the http request object
        
        json.query(forEach: #"$[?(@.service)]"#) { service in
            if let serviceName = service[halfHitch: "service"],
               let serviceActor = services[serviceName] {
                let serviceIndex = servicesCalled
                
                servicesCalled += 1
                serviceActor.beHandleRequest(jsonElement: service,
                                             httpRequest: httpRequest,
                                             self) { result in
                    results.set(value: result, at: serviceIndex)
                    
                    print("1: \(results)")
                    servicesFinished += 1
                    if servicesFinished == servicesCalled {
                        print("2: \(results)")
                        connection.beSendData(HttpResponse.asData(self, .ok, .json, results.description))
                    }
                }
            }
        }
        
        if servicesCalled == 0 {
            connection.beSendInternalError()
        }
    }
}

// MARK: - Autogenerated by FlynnLint
// Contents of file after this marker will be overwritten as needed

extension UserServicableSession {

    @discardableResult
    public func beAdd(service: ServiceActor) -> Self {
        unsafeSend { self._beAdd(service: service) }
        return self
    }
    @discardableResult
    public func beRemove(service: ServiceActor) -> Self {
        unsafeSend { self._beRemove(service: service) }
        return self
    }

}
