import Flynn
import Foundation
import Hitch
import Spanker
import Gzip

let hitchContentTransferEncodingBinary: HalfHitch = "Content-Transfer-Encoding: binary"
let hitchContentDispositionFormat: HalfHitch = #"Content-Disposition: attachment; filename="{0}""#


public extension HttpResponse {
    convenience init(json: JsonElement,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     cacheRevalidateAge: Int = 0,
                     eTag: HalfHitch? = nil,
                     request: HttpRequest? = nil) {
        let payload = json.toHitch()
        if request?.supportsGzip == true {
            self.init(status: .ok,
                      type: .json,
                      payload: (try? payload.dataNoCopy().gzipped(level: .bestSpeed)) ?? payload,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        } else {
            self.init(status: .ok,
                      type: .json,
                      payload: payload,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        }
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
                     cacheRevalidateAge: Int = 0,
                     eTag: HalfHitch? = nil,
                     request: HttpRequest? = nil) {
        if request?.supportsGzip == true {
            self.init(status: .ok,
                      type: .html,
                      payload: (try? html.gzipped(level: .bestSpeed)) ?? html,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        } else {
            self.init(status: .ok,
                      type: .html,
                      payload: html,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        }
    }
    
    convenience init(text: Payloadable,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     cacheRevalidateAge: Int = 0,
                     eTag: HalfHitch? = nil,
                     request: HttpRequest? = nil) {
        if request?.supportsGzip == true {
            self.init(status: .ok,
                      type: .txt,
                      payload: (try? text.gzipped(level: .bestSpeed)) ?? text,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        } else {
            self.init(status: .ok,
                      type: .txt,
                      payload: text,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        }
    }
    
    convenience init(javascript: Payloadable,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     cacheRevalidateAge: Int = 0,
                     eTag: HalfHitch? = nil,
                     request: HttpRequest? = nil) {
        if request?.supportsGzip == true {
            self.init(status: .ok,
                      type: .js,
                      payload: (try? javascript.gzipped(level: .bestSpeed)) ?? javascript,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        } else {
            self.init(status: .ok,
                      type: .js,
                      payload: javascript,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        }
    }
    
    convenience init(json: Payloadable,
                     headers: [HalfHitch]? = nil,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     cacheRevalidateAge: Int = 0,
                     eTag: HalfHitch? = nil,
                     request: HttpRequest? = nil) {
        if request?.supportsGzip == true {
            self.init(status: .ok,
                      type: .json,
                      payload: (try? json.gzipped(level: .bestSpeed)) ?? json,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        } else {
            self.init(status: .ok,
                      type: .json,
                      payload: json,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge,
                      cacheRevalidateAge: cacheRevalidateAge,
                      eTag: eTag)
        }
    }
    
    convenience init(filename: HalfHitch,
                     type: HttpContentType,
                     payload: Payloadable,
                     encoding: HalfHitch? = nil,
                     lastModified: Date? = nil,
                     cacheMaxAge: Int = 0,
                     cacheRevalidateAge: Int = 0,
                     eTag: HalfHitch? = nil,
                     request: HttpRequest? = nil) {
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
                  cacheRevalidateAge: cacheRevalidateAge,
                  eTag: eTag)
    }

}

