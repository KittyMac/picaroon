import Flynn
import Foundation
import Socket

extension Picaroon {
    public struct HttpResponse {

        public static let lastModified = "\(Date())"

        public static func isNew(_ request: HttpRequest) -> Bool {
            if let modifiedDate = request.ifModifiedSince {
                return lastModified != modifiedDate
            }
            return true
        }

        public static func asData(_ session: Picaroon.UserSession?,
                                  _ status: HttpStatus,
                                  _ type: HttpContentType,
                                  _ payload: Data) -> Data {
            var combined = Data(capacity: payload.count + 500)

            let header = """
            HTTP/1.1 \(status.rawValue) \(status.string)
            Content-Type: \(type.string)
            Content-Length:\(payload.count)
            Set-Cookie: \(Picaroon.userSessionCookie)=\(session?.unsafeSessionUUID ?? ""); HttpOnly
            Connection: keep-alive
            Server: Picaroon
            Last-Modified:\(lastModified)\n\n
            """
            combined.append(Data(header.utf8))
            combined.append(payload)

            return combined
        }

        public static func asData(_ session: Picaroon.UserSession?,
                                  _ status: HttpStatus,
                                  _ type: HttpContentType,
                                  _ payload: String) -> Data {
            let payloadUtf8 = payload.utf8

            var combined = Data(capacity: payloadUtf8.count + 500)

            let header = """
            HTTP/1.1 \(status.rawValue) \(status.string)
            Content-Type: \(type.string)
            Content-Length:\(payloadUtf8.count)
            Set-Cookie: \(Picaroon.userSessionCookie)=\(session?.unsafeSessionUUID ?? ""); HttpOnly
            Connection: keep-alive
            Server: Picaroon
            Last-Modified:\(lastModified)

            \(payloadUtf8)
            """
            combined.append(Data(header.utf8))

            return combined
        }

        public static func asData(_ session: Picaroon.UserSession?,
                                  _ status: HttpStatus,
                                  _ type: HttpContentType) -> Data {
            return asData(session, status, type, status.string)
        }
    }
}
