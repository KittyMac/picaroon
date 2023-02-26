import Flynn
import Foundation
import Hitch
import Spanker

public final class HttpStaticResponse: HttpResponse {
    
    public static let success = HttpStaticResponse(status: .ok, type: .txt)
    
    public static let notModified = HttpStaticResponse(status: .notModified, type: .none)
    public static let badRequest = HttpStaticResponse(status: .badRequest, type: .txt)
    public static let unauthorized = HttpStaticResponse(status: .unauthorized, type: .txt)
    public static let notFound = HttpStaticResponse(status: .notFound, type: .txt)
    public static let requestTimeout = HttpStaticResponse(status: .requestTimeout, type: .txt)
    public static let requestTooLarge = HttpStaticResponse(status: .requestTooLarge, type: .txt)
    public static let internalServerError = HttpStaticResponse(status: .internalServerError, type: .txt)
    public static let serviceUnavailable = HttpStaticResponse(status: .serviceUnavailable, type: .txt)
    
    let baked = Hitch()
    
    override func postInit() {
        process(config: nil,
                hitch: baked,
                socket: nil,
                userSession: nil)
    }
    
    override func send(config: ServerConfig,
                       socket: SocketSendable,
                       userSession: UserSession?) {
        socket.send(hitch: baked)
    }
}
