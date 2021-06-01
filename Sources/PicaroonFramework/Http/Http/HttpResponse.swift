import Flynn
import Foundation
import Socket

// swiftlint:disable line_length

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
                              headers: [String]? = nil,
                              encoding: String? = nil,
                              lastModified: Date = sharedLastModifiedDate,
                              cacheMaxAge: Int = 0) -> Data {
        var combinedData = Data(capacity: payload.count + 500)

        var combinedString = String()
        combinedString.reserveCapacity(500)

        combinedString.append(status.string)
        combinedString.append("\r\n")

        if cacheMaxAge > 0 {
            combinedString.append("Cache-Control: public, max-age=\(cacheMaxAge)\r\n")
        }
        if let session = session {
            combinedString.append("Set-Cookie: \(Picaroon.userSessionCookie)=\(session.unsafeSessionUUID.prefix(36)); HttpOnly\r\n")
            for header in session.unsafeSessionHeaders {
                combinedString.append("\(header)\r\n")
            }
        }
        if let encoding = encoding {
            combinedString.append("Content-Encoding: \(encoding)\r\n")
        }

        if let headers = headers {
            for header in headers {
                combinedString.append("\(header)\r\n")
            }
        }

        combinedString.append("Content-Type: \(type.string)\r\n")
        combinedString.append("Content-Length:\(payload.count)\r\n")
        combinedString.append("Connection: keep-alive\r\n")
        combinedString.append("Server: Picaroon\r\n")
        combinedString.append("Last-Modified:\(lastModified)\r\n\r\n")

        combinedData.append(Data(combinedString.utf8))
        combinedData.append(payload)

        return combinedData
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType,
                              _ payload: String,
                              headers: [String]? = nil,
                              encoding: String? = nil,
                              lastModified: Date = sharedLastModifiedDate,
                              cacheMaxAge: Int = 0) -> Data {

        return asData(session,
                      status,
                      type,
                      payload.data(using: .utf8)!,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge)
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType) -> Data {
        return asData(session, status, type, status.string)
    }

    public static func asFile(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType,
                              _ filename: String,
                              _ payload: Data) -> Data {
        return asData(session,
                      status,
                      .zip,
                      payload,
                      headers: [
            "Content-Transfer-Encoding: binary",
            "Content-Disposition: attachment; filename=\"\(filename)\""
        ])
    }

}
