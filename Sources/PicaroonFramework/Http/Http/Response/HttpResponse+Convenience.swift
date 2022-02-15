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
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .json,
                  payload: json.toHitch(),
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
}

// MARK: - HalfHitch

public extension HttpResponse {
    
    convenience init(html: HalfHitch,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .html,
                  payload: html,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(text: HalfHitch,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .txt,
                  payload: text,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(javascript: HalfHitch,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .js,
                  payload: javascript,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(json: HalfHitch,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .json,
                  payload: json,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(filename: HalfHitch,
                     type: HttpContentType,
                     payload: ConvertableToPayloadable,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: type,
                  payload: payload,
                  headers: [
                    hitchContentTransferEncodingBinary,
                    Hitch(#"Content-Disposition: attachment; filename="{0}""#, filename).halfhitch()
                  ],
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
}

// MARK: - Data

public extension HttpResponse {
    
    convenience init(html: Data,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .html,
                  payload: html,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(text: Data,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .txt,
                  payload: text,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(javascript: Data,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .js,
                  payload: javascript,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(json: Data,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .json,
                  payload: json,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(filename: Data,
                     type: HttpContentType,
                     payload: ConvertableToPayloadable,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: type,
                  payload: payload,
                  headers: [
                    hitchContentTransferEncodingBinary,
                    Hitch(#"Content-Disposition: attachment; filename="{0}""#, filename).halfhitch()
                  ],
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
}

