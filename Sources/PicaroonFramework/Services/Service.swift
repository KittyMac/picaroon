import Flynn
import Foundation
import Socket
import Hitch
import Spanker

/// A service is an actor which generically provides additional functionality to a
/// UserServicableSession.
public protocol Service: Actor {
    var unsafeServiceName: Hitch { get }
    
    @discardableResult
    func beHandleRequest(jsonElement: JsonElement,
                         httpRequest: HttpRequest,
                         _ sender: Actor,
                         _ callback: @escaping ((JsonElement) -> Void)) -> Self
}
//open class Service: Actor {
//    func safeServiceName() -> Hitch {
//        fatalError("Service subclass does not override safeServiceName()")
//    }
//
//    private func _beServiceName() -> Hitch {
//        return safeServiceName()
//    }
//
//    private func _beHandleRequest(jsonElement: JsonElement,
//                                  httpRequest: HttpRequest) {
//
//    }
//}
