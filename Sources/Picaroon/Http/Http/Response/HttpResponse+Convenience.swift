import Flynn
import Foundation
import Hitch
import Spanker

let hitchContentTransferEncodingBinary: HalfHitch = "Content-Transfer-Encoding: binary"
let hitchContentDispositionFormat: HalfHitch = #"Content-Disposition: attachment; filename="{0}""#


public extension HttpResponse {
    convenience init(json: JsonElement,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     eTag: HalfHitch? = nil) {
        self.init(status: .ok,
                  type: .json,
                  payload: json.toHitch(),
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge,
                  eTag: eTag)
    }
}

public extension HttpResponse {
    
    convenience init(error: HalfHitch) {
        self.init(status: .badRequest,
                  type: .txt,
                  payload: error)
    }
    
    convenience init(html: Payloadable,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     eTag: HalfHitch? = nil) {
        self.init(status: .ok,
                  type: .html,
                  payload: html,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge,
                  eTag: eTag)
    }
    
    convenience init(text: Payloadable,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     eTag: HalfHitch? = nil) {
        self.init(status: .ok,
                  type: .txt,
                  payload: text,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge,
                  eTag: eTag)
    }
    
    convenience init(javascript: Payloadable,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     eTag: HalfHitch? = nil) {
        self.init(status: .ok,
                  type: .js,
                  payload: javascript,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge,
                  eTag: eTag)
    }
    
    convenience init(json: Payloadable,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     eTag: HalfHitch? = nil) {
        self.init(status: .ok,
                  type: .json,
                  payload: json,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge,
                  eTag: eTag)
    }
    
    convenience init(filename: HalfHitch,
                     type: HttpContentType,
                     payload: Payloadable,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     eTag: HalfHitch? = nil) {
        self.init(status: .ok,
                  type: type,
                  payload: payload,
                  headers: [
                    hitchContentTransferEncodingBinary,
                    #"Content-Disposition: attachment; filename="{0}""# << [filename]
                  ],
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge,
                  eTag: eTag)
    }

}

