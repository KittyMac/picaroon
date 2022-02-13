import Flynn
import Foundation
import Hitch
import Spanker

public final class HttpStaticResponse: HttpResponse {
    
    public static let internalServerError = HttpStaticResponse(status: .internalServerError, type: .txt)
    public static let serviceUnavailable = HttpStaticResponse(status: .serviceUnavailable, type: .txt)
    public static let badRequest = HttpStaticResponse(status: .badRequest, type: .txt)
    
    let baked = Hitch()
    
    override func postInit() {
        process(hitch: baked,
                socket: nil,
                userSession: nil)
    }
    
    override func send(socket: SocketSendable,
              userSession: UserSession?) {
        socket.send(hitch: baked)
    }
}
