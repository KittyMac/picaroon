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
/// to the UserServiceableSession. All requests to the admin service to admin service can
/// now be fulfilled (for a non-admin, these request will fail to match a service and will
/// will result in error. For the authenticated admin user, it will match the service
/// and process normally).
///
/// Note: The name of the service is name of the class as returned by
/// String(describing: type(of: service))
open class UserServiceableSession: UserSession {
    private var values = [Hitch: Hitch]()
    
    internal func _beSet(key: Hitch,
                        value: Hitch) {
        self.values[key] = value
    }
    
    internal func _beGet(key: Hitch) -> Hitch? {
        return values[key]
    }
    
    private var services = [HalfHitch: ServiceActor]()
    
    internal func _beAdd(service: ServiceActor) {
        self.services[service.unsafeServiceName.halfhitch()] = service
    }
    
    private func remove(serviceKey: HalfHitch) {
        guard let service = services[serviceKey] else { return }
        self.services[serviceKey] = nil
        service.beHandleShutdown(self) { }
    }
    
    internal func _beRemove(name: Hitch) {
        remove(serviceKey: name.halfhitch())
    }
    
    internal func _beRemoveAll() {
        for serviceKey in services.keys {
            remove(serviceKey: serviceKey)
        }
    }
    
            
    open override func safeHandleServiceRequest(connection: AnyConnection,
                                                httpRequest: HttpRequest) -> Bool {
        guard let json = httpRequest.json else {
            return false
        }
        
        // Input: We allow sending an array of service commands
        // [{"service":"HelloWorldService"},{"service":"AdminUserService","command":"DeleteUser"}]
        
        // Output: We expect an array of results
        // [{"service":"HelloWorldService", "result":"Hello World"}, {"service":"AdminUserService","error":"500"}]
        let jsonResponses = ^[]
        var httpResponses = [HttpResponse]()
        var servicesCalled = 0
        var servicesFinished = 0
        
        json.query(forEach: #"$[?(@.service)]"#) { service in
            if let serviceName = service[halfHitch: "service"],
               let serviceActor = services[serviceName] {
                let serviceIndex = servicesCalled
                
                servicesCalled += 1
                serviceActor.beHandleRequest(userSession: self,
                                             jsonElement: service,
                                             httpRequest: httpRequest,
                                             self) { jsonResponse, httpResponse in
                    
                    jsonResponses.set(value: jsonResponse, at: serviceIndex)
                    if let httpResponse = httpResponse {
                        httpResponses.append(httpResponse)
                    }
                    
                    servicesFinished += 1
                    if servicesFinished == servicesCalled {
                        // The problem is can potentially have many services, and these services all want to return something.
                        // Those "somethings" are one of two things:
                        // 1. JSON formatted results
                        // 2. A full HTTP response (such as pre-gzipped HTML, etc)
                        //
                        // We attempted to solve this generically by sending back multipart formdata http responses, but it
                        // is not possible to send these back generically enough (some might want to be gzipped while others
                        // might not want to be, for example). Our compromise is the following system:
                        //
                        // 1. All JSON responses are gathered together into a single array (or a single dictionary if there is only one).
                        //    This combined JSON is attached to an http header "Service-Response"
                        // 2. If none of the services include an http response, we make a simple 0 content success and send it
                        // 3. If there is exactly one http response, we attach the headers from step 1 and send it
                        // 4. If there are more then one http response, we send internal service error and attach header from step 1 and send it
                        
                        var headers = [HalfHitch]()
                        if jsonResponses.count > 0 {
                            let serviceResponseHeader = Hitch(string: "Service-Response:")
                            if let jsonResponse = jsonResponses[element: 0],
                               jsonResponses.count == 1 {
                                jsonResponse.exportTo(hitch: serviceResponseHeader)
                            } else {
                                jsonResponses.exportTo(hitch: serviceResponseHeader)
                            }
                            headers.append(serviceResponseHeader.halfhitch())
                        }
                        
                        if httpResponses.count == 0 {
                            connection.beSend(httpResponse: HttpResponse(text: "",
                                                                         headers: headers))
                        } else if httpResponses.count == 1 {
                            connection.beSend(httpResponse: HttpResponse(httpResponse: httpResponses[0],
                                                                         headers: headers))
                        } else {
                            connection.beSend(httpResponse: HttpResponse(status: .internalServerError,
                                                                         type: .txt,
                                                                         payload: HttpStatus.internalServerError.hitch,
                                                                         headers: headers))
                        }
                    }
                }
            }
        }
        
        return servicesCalled > 0
    }
}
