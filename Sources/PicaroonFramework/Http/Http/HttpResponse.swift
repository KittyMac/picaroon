import Flynn
import Foundation
import Socket

// swiftlint:disable line_length

private let newlineData = "\r\n".data(using: .utf8)!

private let boundaryHeader = "\(UUID().uuidString)"
private let boundaryEndString = "--\(boundaryHeader)--\r\n"
private let boundaryEndData = boundaryEndString.data(using: .utf8)!

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
                              encoding: String? = nil,
                              lastModified: Date = sharedLastModifiedDate,
                              cacheMaxAge: Int = 0) -> Data {
        var combinedData = Data(capacity: payload.count + 512)

        var combinedString = String()
        combinedString.reserveCapacity(512)

        combinedString.append(status.string)
        combinedString.append("\r\n")

        if cacheMaxAge > 0 {
            combinedString.append("Cache-Control: public, max-age=\(cacheMaxAge)\r\n")
        }
        if let session = session {
            combinedString.append("Set-Cookie: \(Picaroon.userSessionCookie)=\(session.unsafeSessionUUID); HttpOnly\r\n")
        }
        if let encoding = encoding {
            combinedString.append("Content-Encoding: \(encoding)\r\n")
        }

        if type == .multipartFormData {
            combinedString.append("Content-Type: multipart/form-data; boundary=\(boundaryHeader)\r\n")
        } else {
            combinedString.append("Content-Type: \(type.string)\r\n")
        }

        combinedString.append("""
        Content-Length:\(payload.count)\r\n
        Connection: keep-alive\r\n
        Server: Picaroon\r\n
        Last-Modified:\(lastModified)\r\n\r\n
        """)

        combinedData.append(Data(combinedString.utf8))
        combinedData.append(payload)

        return combinedData
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType,
                              _ payload: String,
                              encoding: String? = nil,
                              lastModified: Date = sharedLastModifiedDate,
                              cacheMaxAge: Int = 0) -> Data {

        return asData(session,
                      status,
                      type,
                      payload.data(using: .utf8)!,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge)
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType) -> Data {
        return asData(session, status, type, status.string)
    }

    public static func asMultipartData(_ session: UserSession?,
                                       _ status: HttpStatus,
                                       _ payloads: [Data]) -> Data {

        var combined = Data()
        combined.reserveCapacity(payloads.reduce(0) { $0 + $1.count } + 512)
        for data in payloads {
            combined.append(data)
        }
        combined.append(boundaryEndData)

        return asData(session,
                      status,
                      .multipartFormData,
                      combined)
    }

    public static func asPart(_ name: String,
                              _ type: HttpContentType,
                              _ payload: Data,
                              encoding: String? = nil) -> Data {
        var combinedData = Data(capacity: payload.count + 512)

        var combinedString = String()
        combinedString.reserveCapacity(512)

        combinedString.append("--\(boundaryHeader)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n")
        combinedString.append("Content-Type: \(type.string)\r\n")

        if let encoding = encoding {
            combinedString.append("Content-Encoding: \(encoding)\r\n")
        }
        combinedString.append("Content-Length:\(payload.count)\r\n")

        combinedData.append(Data(combinedString.utf8))
        combinedData.append(payload)
        combinedData.append(newlineData)

        return combinedData
    }

    public static func asPart(_ name: String,
                              _ type: HttpContentType,
                              _ payload: String,
                              encoding: String? = nil) -> Data {
        return asPart(name, type, payload.data(using: .utf8)!,
                      encoding: encoding)
    }

}
