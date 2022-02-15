import Flynn
import Foundation
import Hitch
import Spanker

let hitchContentTransferEncodingBinary: HalfHitch = "Content-Transfer-Encoding: binary"
let hitchContentDispositionFormat: HalfHitch = #"Content-Disposition: attachment; filename="{0}""#


public extension HttpResponse {
    convenience init(json: JsonElement,
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .json,
                  payload: json.toHitch(),
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
}

// MARK: - HALFHITCH

public extension HttpResponse {
    
    convenience init(html: Hitch,
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .html,
                  payload: html,
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(text: Hitch,
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .txt,
                  payload: text,
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(javascript: Hitch,
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .js,
                  payload: javascript,
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(json: Hitch,
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .json,
                  payload: json,
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(filename: Hitch,
                     name: Hitch? = nil,
                     type: HttpContentType,
                     payload: ConvertableToPayloadable,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: type,
                  payload: payload,
                  name: name,
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
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .html,
                  payload: html,
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(text: Data,
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .txt,
                  payload: text,
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(javascript: Data,
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .js,
                  payload: javascript,
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(json: Data,
                     name: Hitch? = nil,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: .json,
                  payload: json,
                  name: name,
                  headers: headers,
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
    
    convenience init(filename: Data,
                     name: Hitch? = nil,
                     type: HttpContentType,
                     payload: ConvertableToPayloadable,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0) {
        self.init(status: .ok,
                  type: type,
                  payload: payload,
                  name: name,
                  headers: [
                    hitchContentTransferEncodingBinary,
                    Hitch(#"Content-Disposition: attachment; filename="{0}""#, filename).halfhitch()
                  ],
                  encoding: encoding,
                  lastModified: lastModified,
                  cacheMaxAge: cacheMaxAge)
    }
}

