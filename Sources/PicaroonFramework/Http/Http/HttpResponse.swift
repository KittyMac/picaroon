import Flynn
import Foundation
import Socket

public struct HttpResponse {

    public static let sharedLastModifiedDate = Date()
    public static let sharedLastModifiedDateString = "\(sharedLastModifiedDate)"

    public static func isNew(_ request: HttpRequest) -> Bool {
        if let modifiedDate = request.ifModifiedSince {
            return sharedLastModifiedDateString != modifiedDate
        }
        return true
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType,
                              _ payload: Data,
                              _ encoding: String = "identity",
                              _ lastModified: Date = sharedLastModifiedDate) -> Data {
        var combined = Data(capacity: payload.count + 500)

        if let session = session {
            let header = """
            \(status.string)\r
            Content-Type: \(type.string)\r
            Content-Length:\(payload.count)\r
            Set-Cookie: \(Picaroon.userSessionCookie)=\(session.unsafeSessionUUID); HttpOnly\r
            Content-Encoding: \(encoding)\r
            Connection: keep-alive\r
            Server: Picaroon\r
            Last-Modified:\(lastModified)\r\n\r\n
            """
            combined.append(Data(header.utf8))
            combined.append(payload)
        } else {
            let header = """
            \(status.string)\r
            Content-Type: \(type.string)\r
            Content-Length:\(payload.count)\r
            Content-Encoding: \(encoding)\r
            Connection: keep-alive\r
            Server: Picaroon\r
            Last-Modified:\(lastModified)\r\n\r\n
            """
            combined.append(Data(header.utf8))
            combined.append(payload)
        }

        return combined
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType,
                              _ payload: String,
                              _ encoding: String = "identity",
                              _ lastModified: Date = sharedLastModifiedDate) -> Data {
        let payloadUtf8 = payload.utf8

        var combined = Data(capacity: payloadUtf8.count + 500)

        if let session = session {
            let header = """
            \(status.string)\r
            Content-Type: \(type.string)\r
            Content-Length:\(payloadUtf8.count)\r
            Set-Cookie: \(Picaroon.userSessionCookie)=\(session.unsafeSessionUUID); HttpOnly\r
            Content-Encoding: \(encoding)\r
            Connection: keep-alive\r
            Server: Picaroon\r
            Last-Modified:\(lastModified)\r
            \r
            \(payloadUtf8)
            """
            combined.append(Data(header.utf8))
        } else {
            let header = """
            \(status.string)\r
            Content-Type: \(type.string)\r
            Content-Length:\(payloadUtf8.count)\r
            Content-Encoding: \(encoding)\r
            Connection: keep-alive\r
            Server: Picaroon\r
            Last-Modified:\(lastModified)\r
            \r
            \(payloadUtf8)
            """
            combined.append(Data(header.utf8))
        }

        return combined
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType) -> Data {
        return asData(session, status, type, status.string)
    }
}
