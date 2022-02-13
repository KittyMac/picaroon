import Flynn
import Foundation
import Hitch
import Spanker

public extension HttpResponse {
    convenience init(text: Hitch,
                     multipartName: Hitch? = nil,
                     headers: [Hitchable]? = nil,
                     encoding: Hitchable? = nil,
                     lastModified: Date = sharedLastModifiedDate,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .txt,
                  payload: text,
                  multipartName: multipartName,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(javascript: Hitch,
                     multipartName: Hitch? = nil,
                     headers: [Hitchable]? = nil,
                     encoding: Hitchable? = nil,
                     lastModified: Date = sharedLastModifiedDate,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .js,
                  payload: javascript,
                  multipartName: multipartName,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(json: Hitch,
                     multipartName: Hitch? = nil,
                     headers: [Hitchable]? = nil,
                     encoding: Hitchable? = nil,
                     lastModified: Date = sharedLastModifiedDate,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .json,
                  payload: json,
                  multipartName: multipartName,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(json: JsonElement,
                     multipartName: Hitch? = nil,
                     headers: [Hitchable]? = nil,
                     encoding: Hitchable? = nil,
                     lastModified: Date = sharedLastModifiedDate,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .json,
                  payload: json.toHitch(),
                  multipartName: multipartName,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(filename: Hitch,
                     type: HttpContentType,
                     payload: Payloadable,
                     multipartName: Hitch? = nil,
                     encoding: Hitchable? = nil,
                     lastModified: Date = sharedLastModifiedDate,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: type,
                  payload: payload,
                  multipartName: multipartName,
                  headers: [
                    "Content-Transfer-Encoding: binary",
                    Hitch(#"Content-Disposition: attachment; filename="{0}""#, filename)
                  ],
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
}
