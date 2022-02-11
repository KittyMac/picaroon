import Flynn
import Foundation
import Hitch
import Spanker

// swiftlint:disable function_body_length
// swiftlint:disable cyclomatic_complexity
// swiftlint:disable identifier_name
// swiftlint:disable type_body_length
// swiftlint:disable file_length

public class HttpRequest {
    
    public var method: HttpMethod?
    
    public var url: HalfHitch?
    public var urlParameters: HalfHitch?
    public var host: HalfHitch?
    public var userAgent: HalfHitch?
    public var accept: HalfHitch?
    public var acceptEncoding: HalfHitch?
    public var acceptCharset: HalfHitch?
    public var acceptLanguage: HalfHitch?
    public var connection: HalfHitch?
    public var upgradeInsecureRequests: HalfHitch?
    public var contentLength: HalfHitch?
    public var contentType: HalfHitch?
    public var contentDisposition: HalfHitch?
    public var ifModifiedSince: HalfHitch?
    public var cookie: HalfHitch?
    public var expect: HalfHitch?
    public var flynnTag: HalfHitch?
    public var sessionId: HalfHitch?
    public var sid: HalfHitch?
    
    public var content: HalfHitch?
    public var json: JsonElement?
    
    public var description: Hitch?
    
    public var cookies: [String: String] {
        var _cookies: [String: String] = [:]

        if let cookie = cookie {
            // cookie1=something; cookie2=another
            let keyValuePairs = cookie.description.components(separatedBy: ";")
            for pair in keyValuePairs {
                let parts = pair.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "=")
                if parts.count == 2 {
                    _cookies[parts[0]] = parts[1]
                }
            }
        }
        return _cookies
    }
    
    public init?(request buffer: UnsafeMutablePointer<UInt8>,
                 size bufferSize: Int) {
        
        let startPtr = buffer
        let endPtr = buffer + bufferSize
        var ptr = startPtr + 3
        var lineNumber = 0

        while ptr < endPtr {
            var size = ptr - startPtr

            if lineNumber == 0 {
                if method == nil {
                    if  size >= 3 &&
                        (ptr-3).pointee == UInt8.G &&
                        (ptr-2).pointee == UInt8.E &&
                        (ptr-1).pointee == UInt8.T &&
                        ptr.pointee == UInt8.space {
                        method = .GET
                    } else if
                        size >= 4 &&
                        (ptr-4).pointee == UInt8.H &&
                        (ptr-3).pointee == UInt8.E &&
                        (ptr-2).pointee == UInt8.A &&
                        (ptr-1).pointee == UInt8.D &&
                        ptr.pointee == UInt8.space {
                        method = .HEAD
                    } else if
                        size >= 3 &&
                        (ptr-3).pointee == UInt8.P &&
                        (ptr-2).pointee == UInt8.U &&
                        (ptr-1).pointee == UInt8.T &&
                        ptr.pointee == UInt8.space {
                        method = .PUT
                    } else if
                        size >= 4 &&
                        (ptr-4).pointee == UInt8.P &&
                        (ptr-3).pointee == UInt8.O &&
                        (ptr-2).pointee == UInt8.S &&
                        (ptr-1).pointee == UInt8.T &&
                        ptr.pointee == UInt8.space {
                        method = .POST
                    } else if
                        size >= 6 &&
                        (ptr-6).pointee == UInt8.D &&
                        (ptr-5).pointee == UInt8.E &&
                        (ptr-4).pointee == UInt8.L &&
                        (ptr-3).pointee == UInt8.E &&
                        (ptr-2).pointee == UInt8.T &&
                        (ptr-1).pointee == UInt8.E &&
                        ptr.pointee == UInt8.space {
                        method = .DELETE
                    }

                    // We identified the method, now parse the rest of the line
                    if method != nil {
                        let defaultPtr = ptr + 1

                        var urlParametersStartPtr = defaultPtr
                        var urlParametersEndPtr = defaultPtr
                        var sessionStartPtr = defaultPtr
                        var sessionEndPtr = defaultPtr
                        let urlStartPtr = defaultPtr
                        var urlEndPtr = defaultPtr

                        ptr += 1

                        while ptr < endPtr {
                            size = ptr - startPtr

                            if urlParametersStartPtr == defaultPtr &&
                                (ptr-1).pointee == UInt8.questionMark {
                                urlParametersStartPtr = ptr
                            }

                            if  size >= 4 &&
                                (ptr-4).pointee == UInt8.s &&
                                (ptr-3).pointee == UInt8.i &&
                                (ptr-2).pointee == UInt8.d &&
                                (ptr-1).pointee == UInt8.equal {
                                sessionStartPtr = ptr
                            }

                            if  size >= 6 &&
                                (ptr-6).pointee == UInt8.s &&
                                (ptr-5).pointee == UInt8.i &&
                                (ptr-4).pointee == UInt8.d &&
                                (ptr-3).pointee == UInt8.percentSign &&
                                (ptr-2).pointee == UInt8.three &&
                                ((ptr-1).pointee == UInt8.D || (ptr-1).pointee == UInt8.d) {
                                sessionStartPtr = ptr
                            }

                            if ptr.pointee == UInt8.ampersand &&
                                sessionStartPtr != defaultPtr {
                                sessionEndPtr = ptr
                            }

                            if ptr.pointee == UInt8.carriageReturn ||
                                ptr.pointee == UInt8.newLine ||
                                ptr.pointee == UInt8.space {

                                if sessionStartPtr != defaultPtr &&
                                    sessionEndPtr == defaultPtr {
                                    sessionEndPtr = ptr
                                }
                                if urlParametersStartPtr != defaultPtr {
                                    urlParametersEndPtr = ptr
                                    urlEndPtr = urlParametersStartPtr - 1
                                } else {
                                    urlEndPtr = ptr
                                }
                                break
                            }

                            ptr += 1
                        }
                        
                        
                        url = HalfHitch(raw: buffer,
                                        count: bufferSize,
                                        from: urlStartPtr - buffer,
                                        to: urlEndPtr - buffer)
                        
                        if sessionStartPtr < sessionEndPtr {
                            sid = HalfHitch(raw: buffer,
                                            count: bufferSize,
                                            from: sessionStartPtr - buffer,
                                            to: sessionEndPtr - buffer)
                        }
                        if urlParametersStartPtr < urlParametersEndPtr {
                            urlParameters = HalfHitch(raw: buffer,
                                                      count: bufferSize,
                                                      from: urlParametersStartPtr - buffer,
                                                      to: urlParametersEndPtr - buffer)
                        }
                    }
                }
            } else {
                // Every line after the header is a Key-Word-No-Space: Whatever Until New Line
                // 1. advance until we find the ":", or a whitespace
                var keyEnd = ptr + 1
                while ptr < endPtr {
                    if ptr.pointee == UInt8.carriageReturn || ptr.pointee == UInt8.newLine {
                        while ptr < endPtr && ( ptr.pointee == UInt8.carriageReturn ||
                                                ptr.pointee == UInt8.newLine) {
                            ptr += 1
                        }
                        // If we reach here, we're at the point we're looking for payload data
                        if let contentLength = contentLength {
                            if let contentLengthBytes = contentLength.toInt() {
                                if endPtr - ptr >= contentLengthBytes {
                                    content = HalfHitch(raw: buffer,
                                                        count: bufferSize,
                                                        from: ptr - buffer,
                                                        to: (ptr - buffer) + contentLengthBytes)
                                }
                            }
                        }
                        
                        // Congrats! we have successfully parsed the http request. We now need to bake the request
                        // (ie copy to our own buffer before we pass it along to other people)
                        bake(buffer: buffer,
                             bufferSize: bufferSize)
                        
                        return
                    }
                    if ptr.pointee == UInt8.colon {
                        keyEnd = ptr
                        ptr += 1
                        break
                    }
                    ptr += 1
                }

                // 2. Skip whitespace
                while ptr < endPtr && (ptr.pointee == UInt8.space || ptr.pointee == UInt8.tab) {
                    ptr += 1
                }

                let valueStart = ptr

                // 3. Advance to the end of the line
                while ptr < endPtr && ptr.pointee != UInt8.carriageReturn && ptr.pointee != UInt8.newLine {
                    ptr += 1
                }

                // 3. For speed, we only match against the keys we support (no generics)
                parseKeyValue(buffer: buffer,
                              bufferSize: bufferSize,
                              ptr: ptr,
                              valueStart: valueStart,
                              keyEnd: keyEnd)

                // Advance to the next line
                if ptr.pointee == UInt8.carriageReturn {
                    ptr += 1
                    if ptr.pointee == UInt8.newLine {
                        ptr += 1
                    }
                } else if ptr.pointee == UInt8.newLine {
                    ptr += 1
                }
            }

            if ptr.pointee == UInt8.newLine {
                lineNumber += 1
                if method == nil {
                    // we should have parsed the HTTP method on the first line, so
                    // exit early since that failed
                    break
                }
            }

            ptr += 1
        }
        
        return nil
    }
    
    public init?(multipart buffer: UnsafeMutablePointer<UInt8>,
                 size bufferSize: Int) {

        let startPtr = buffer
        let endPtr = buffer + bufferSize

        var ptr = startPtr + 3

        var lineNumber = 0

        while ptr < endPtr {
            // Every line after the header is a Key-Word-No-Space: Whatever Until New Line
            // 1. advance until we find the ":", or a whitespace
            var keyEnd = ptr + 1
            while ptr < endPtr {
                if ptr.pointee == UInt8.carriageReturn || ptr.pointee == UInt8.newLine {
                    while ptr < endPtr && ( ptr.pointee == UInt8.carriageReturn ||
                                            ptr.pointee == UInt8.newLine) {
                        ptr += 1
                    }

                    // If we reach here, the rest of the content is the payload
                    if endPtr - ptr >= 0 {
                        content = HalfHitch(raw: buffer,
                                            count: bufferSize,
                                            from: ptr - buffer,
                                            to: (ptr - buffer) + (endPtr - ptr))
                    }
                    return
                }
                if ptr.pointee == UInt8.colon {
                    keyEnd = ptr
                    ptr += 1
                    break
                }
                ptr += 1
            }

            // 2. Skip whitespace
            while ptr < endPtr && (ptr.pointee == UInt8.space || ptr.pointee == UInt8.tab) {
                ptr += 1
            }

            let valueStart = ptr

            // 3. Advance to the end of the line
            while ptr < endPtr && ptr.pointee != UInt8.carriageReturn && ptr.pointee != UInt8.newLine {
                ptr += 1
            }

            // 3. For speed, we only match against the keys we support (no generics)
            parseKeyValue(buffer: buffer,
                          bufferSize: bufferSize,
                          ptr: ptr,
                          valueStart: valueStart,
                          keyEnd: keyEnd)

            // Advance to the next line
            if ptr.pointee == UInt8.carriageReturn {
                ptr += 1
                if ptr.pointee == UInt8.newLine {
                    ptr += 1
                }
            } else if ptr.pointee == UInt8.newLine {
                ptr += 1
            }

            if ptr.pointee == UInt8.newLine {
                lineNumber += 1
                if method == nil {
                    // we should have parsed the HTTP method on the first line, so
                    // exit early since that failed
                    break
                }
            }

            ptr += 1
        }
        
        return nil
    }
    
    @inlinable @inline(__always)
    func bake(buffer: UnsafeMutablePointer<UInt8>,
              bufferSize: Int,
              using: HalfHitch?) -> HalfHitch? {
        guard let halfhitch = using else { return nil }
        guard let oldRaw = halfhitch.raw() else { return nil }
        guard let newRaw = description?.raw() else { return nil }
        
        let startIndex = oldRaw - buffer
        
        return HalfHitch(raw: newRaw,
                         count: bufferSize,
                         from: startIndex,
                         to: startIndex + halfhitch.count)
    }
    
    @inlinable @inline(__always)
    func bake(buffer: UnsafeMutablePointer<UInt8>,
              bufferSize: Int) {
        
        description = Hitch(bytes: buffer, offset: 0, count: bufferSize)
                
        url = bake(buffer: buffer, bufferSize: bufferSize, using: url)
        urlParameters = bake(buffer: buffer, bufferSize: bufferSize, using: urlParameters)
        host = bake(buffer: buffer, bufferSize: bufferSize, using: host)
        userAgent = bake(buffer: buffer, bufferSize: bufferSize, using: userAgent)
        accept = bake(buffer: buffer, bufferSize: bufferSize, using: accept)
        acceptEncoding = bake(buffer: buffer, bufferSize: bufferSize, using: acceptEncoding)
        acceptCharset = bake(buffer: buffer, bufferSize: bufferSize, using: acceptCharset)
        acceptLanguage = bake(buffer: buffer, bufferSize: bufferSize, using: acceptLanguage)
        connection = bake(buffer: buffer, bufferSize: bufferSize, using: connection)
        upgradeInsecureRequests = bake(buffer: buffer, bufferSize: bufferSize, using: upgradeInsecureRequests)
        contentLength = bake(buffer: buffer, bufferSize: bufferSize, using: contentLength)
        contentType = bake(buffer: buffer, bufferSize: bufferSize, using: contentType)
        contentDisposition = bake(buffer: buffer, bufferSize: bufferSize, using: contentDisposition)
        ifModifiedSince = bake(buffer: buffer, bufferSize: bufferSize, using: ifModifiedSince)
        cookie = bake(buffer: buffer, bufferSize: bufferSize, using: cookie)
        expect = bake(buffer: buffer, bufferSize: bufferSize, using: expect)
        flynnTag = bake(buffer: buffer, bufferSize: bufferSize, using: flynnTag)
        sessionId = bake(buffer: buffer, bufferSize: bufferSize, using: sessionId)
        sid = bake(buffer: buffer, bufferSize: bufferSize, using: sid)
        content = bake(buffer: buffer, bufferSize: bufferSize, using: content)
        
        // If we have json content, automatically parse it out
        if let content = content {
            json = Spanker.parse(halfhitch: content)
        }
    }
    
    @inlinable @inline(__always)
    func parseKeyValue(buffer: UnsafeMutablePointer<UInt8>,
                       bufferSize: Int,
                       ptr: UnsafeMutablePointer<UInt8>,
                       valueStart: UnsafeMutablePointer<UInt8>,
                       keyEnd: UnsafeMutablePointer<UInt8>) {
        let size = keyEnd - buffer

        if  host == nil &&
            size >= 5 &&
            (keyEnd-4).pointee == UInt8.H &&
            (keyEnd-3).pointee == UInt8.o &&
            (keyEnd-2).pointee == UInt8.s &&
            (keyEnd-1).pointee == UInt8.t {
            host = HalfHitch(raw: buffer,
                             count: bufferSize,
                             from: valueStart - buffer,
                             to: ptr - buffer)
        }

        if  userAgent == nil &&
            size >= 10 &&
            (keyEnd-10).pointee == UInt8.U &&
            (keyEnd-9).pointee == UInt8.s &&
            (keyEnd-8).pointee == UInt8.e &&
            (keyEnd-7).pointee == UInt8.r &&
            (keyEnd-6).pointee == UInt8.minus &&
            (keyEnd-5).pointee == UInt8.A &&
            (keyEnd-4).pointee == UInt8.g &&
            (keyEnd-3).pointee == UInt8.e &&
            (keyEnd-2).pointee == UInt8.n &&
            (keyEnd-1).pointee == UInt8.t {
            userAgent = HalfHitch(raw: buffer,
                                  count: bufferSize,
                                  from: valueStart - buffer,
                                  to: ptr - buffer)
        }

        if  accept == nil &&
            size >= 6 &&
            (keyEnd-6).pointee == UInt8.A &&
            (keyEnd-5).pointee == UInt8.c &&
            (keyEnd-4).pointee == UInt8.c &&
            (keyEnd-3).pointee == UInt8.e &&
            (keyEnd-2).pointee == UInt8.p &&
            (keyEnd-1).pointee == UInt8.t {
            accept = HalfHitch(raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }

        if  acceptEncoding == nil &&
            size >= 15 &&
            (keyEnd-15).pointee == UInt8.A &&
            (keyEnd-14).pointee == UInt8.c &&
            (keyEnd-13).pointee == UInt8.c &&
            (keyEnd-12).pointee == UInt8.e &&
            (keyEnd-11).pointee == UInt8.p &&
            (keyEnd-10).pointee == UInt8.t &&
            (keyEnd-9).pointee == UInt8.minus &&
            (keyEnd-8).pointee == UInt8.E &&
            (keyEnd-7).pointee == UInt8.n &&
            (keyEnd-6).pointee == UInt8.c &&
            (keyEnd-5).pointee == UInt8.o &&
            (keyEnd-4).pointee == UInt8.d &&
            (keyEnd-3).pointee == UInt8.i &&
            (keyEnd-2).pointee == UInt8.n &&
            (keyEnd-1).pointee == UInt8.g {
            acceptEncoding = HalfHitch(raw: buffer,
                                       count: bufferSize,
                                       from: valueStart - buffer,
                                       to: ptr - buffer)
        }

        if  acceptCharset == nil &&
            size >= 14 &&
            (keyEnd-14).pointee == UInt8.A &&
            (keyEnd-13).pointee == UInt8.c &&
            (keyEnd-12).pointee == UInt8.c &&
            (keyEnd-11).pointee == UInt8.e &&
            (keyEnd-10).pointee == UInt8.p &&
            (keyEnd-9).pointee == UInt8.t &&
            (keyEnd-8).pointee == UInt8.minus &&
            (keyEnd-7).pointee == UInt8.C &&
            (keyEnd-6).pointee == UInt8.h &&
            (keyEnd-5).pointee == UInt8.a &&
            (keyEnd-4).pointee == UInt8.r &&
            (keyEnd-3).pointee == UInt8.s &&
            (keyEnd-2).pointee == UInt8.e &&
            (keyEnd-1).pointee == UInt8.t {
            acceptCharset = HalfHitch(raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }

        if  acceptLanguage == nil &&
            size >= 15 &&
            (keyEnd-15).pointee == UInt8.A &&
            (keyEnd-14).pointee == UInt8.c &&
            (keyEnd-13).pointee == UInt8.c &&
            (keyEnd-12).pointee == UInt8.e &&
            (keyEnd-11).pointee == UInt8.p &&
            (keyEnd-10).pointee == UInt8.t &&
            (keyEnd-9).pointee == UInt8.minus &&
            (keyEnd-8).pointee == UInt8.L &&
            (keyEnd-7).pointee == UInt8.a &&
            (keyEnd-6).pointee == UInt8.n &&
            (keyEnd-5).pointee == UInt8.g &&
            (keyEnd-4).pointee == UInt8.u &&
            (keyEnd-3).pointee == UInt8.a &&
            (keyEnd-2).pointee == UInt8.g &&
            (keyEnd-1).pointee == UInt8.e {
            acceptLanguage = HalfHitch(raw: buffer,
                                       count: bufferSize,
                                       from: valueStart - buffer,
                                       to: ptr - buffer)
        }

        if  connection == nil &&
            size >= 10 &&
            (keyEnd-10).pointee == UInt8.C &&
            (keyEnd-9).pointee == UInt8.o &&
            (keyEnd-8).pointee == UInt8.n &&
            (keyEnd-7).pointee == UInt8.n &&
            (keyEnd-6).pointee == UInt8.e &&
            (keyEnd-5).pointee == UInt8.c &&
            (keyEnd-4).pointee == UInt8.t &&
            (keyEnd-3).pointee == UInt8.i &&
            (keyEnd-2).pointee == UInt8.o &&
            (keyEnd-1).pointee == UInt8.n {
            connection = HalfHitch(raw: buffer,
                                   count: bufferSize,
                                   from: valueStart - buffer,
                                   to: ptr - buffer)
        }

        if  upgradeInsecureRequests == nil &&
            size >= 25 &&
            (keyEnd-25).pointee == UInt8.U &&
            (keyEnd-24).pointee == UInt8.p &&
            (keyEnd-23).pointee == UInt8.g &&
            (keyEnd-22).pointee == UInt8.r &&
            (keyEnd-21).pointee == UInt8.a &&
            (keyEnd-20).pointee == UInt8.d &&
            (keyEnd-19).pointee == UInt8.e &&
            (keyEnd-18).pointee == UInt8.minus &&
            (keyEnd-17).pointee == UInt8.I &&
            (keyEnd-16).pointee == UInt8.n &&
            (keyEnd-15).pointee == UInt8.s &&
            (keyEnd-14).pointee == UInt8.e &&
            (keyEnd-13).pointee == UInt8.c &&
            (keyEnd-12).pointee == UInt8.u &&
            (keyEnd-11).pointee == UInt8.r &&
            (keyEnd-10).pointee == UInt8.e &&
            (keyEnd-9).pointee == UInt8.minus &&
            (keyEnd-8).pointee == UInt8.R &&
            (keyEnd-7).pointee == UInt8.e &&
            (keyEnd-6).pointee == UInt8.q &&
            (keyEnd-5).pointee == UInt8.u &&
            (keyEnd-4).pointee == UInt8.e &&
            (keyEnd-3).pointee == UInt8.s &&
            (keyEnd-2).pointee == UInt8.t &&
            (keyEnd-1).pointee == UInt8.s {
            upgradeInsecureRequests = HalfHitch(raw: buffer,
                                                count: bufferSize,
                                                from: valueStart - buffer,
                                                to: ptr - buffer)
        }

        if  contentLength == nil &&
            size >= 14 &&
            (keyEnd-14).pointee == UInt8.C &&
            (keyEnd-13).pointee == UInt8.o &&
            (keyEnd-12).pointee == UInt8.n &&
            (keyEnd-11).pointee == UInt8.t &&
            (keyEnd-10).pointee == UInt8.e &&
            (keyEnd-9).pointee == UInt8.n &&
            (keyEnd-8).pointee == UInt8.t &&
            (keyEnd-7).pointee == UInt8.minus &&
            (keyEnd-6).pointee == UInt8.L &&
            (keyEnd-5).pointee == UInt8.e &&
            (keyEnd-4).pointee == UInt8.n &&
            (keyEnd-3).pointee == UInt8.g &&
            (keyEnd-2).pointee == UInt8.t &&
            (keyEnd-1).pointee == UInt8.h {
            contentLength = HalfHitch(raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }

        if  contentType == nil &&
            size >= 12 &&
            (keyEnd-12).pointee == UInt8.C &&
            (keyEnd-11).pointee == UInt8.o &&
            (keyEnd-10).pointee == UInt8.n &&
            (keyEnd-9).pointee == UInt8.t &&
            (keyEnd-8).pointee == UInt8.e &&
            (keyEnd-7).pointee == UInt8.n &&
            (keyEnd-6).pointee == UInt8.t &&
            (keyEnd-5).pointee == UInt8.minus &&
            (keyEnd-4).pointee == UInt8.T &&
            (keyEnd-3).pointee == UInt8.y &&
            (keyEnd-2).pointee == UInt8.p &&
            (keyEnd-1).pointee == UInt8.e {
            contentType = HalfHitch(raw: buffer,
                                    count: bufferSize,
                                    from: valueStart - buffer,
                                    to: ptr - buffer)
        }

        if  contentDisposition == nil &&
            size >= 19 &&
            (keyEnd-19).pointee == UInt8.C &&
            (keyEnd-18).pointee == UInt8.o &&
            (keyEnd-17).pointee == UInt8.n &&
            (keyEnd-16).pointee == UInt8.t &&
            (keyEnd-15).pointee == UInt8.e &&
            (keyEnd-14).pointee == UInt8.n &&
            (keyEnd-13).pointee == UInt8.t &&
            (keyEnd-12).pointee == UInt8.minus &&
            (keyEnd-11).pointee == UInt8.D &&
            (keyEnd-10).pointee == UInt8.i &&
            (keyEnd-9).pointee == UInt8.s &&
            (keyEnd-8).pointee == UInt8.p &&
            (keyEnd-7).pointee == UInt8.o &&
            (keyEnd-6).pointee == UInt8.s &&
            (keyEnd-5).pointee == UInt8.i &&
            (keyEnd-4).pointee == UInt8.t &&
            (keyEnd-3).pointee == UInt8.i &&
            (keyEnd-2).pointee == UInt8.o &&
            (keyEnd-1).pointee == UInt8.n {
            contentDisposition = HalfHitch(raw: buffer,
                                           count: bufferSize,
                                           from: valueStart - buffer,
                                           to: ptr - buffer)
        }

        if  ifModifiedSince == nil &&
            size >= 17 &&
            (keyEnd-17).pointee == UInt8.I &&
            (keyEnd-16).pointee == UInt8.f &&
            (keyEnd-15).pointee == UInt8.minus &&
            (keyEnd-14).pointee == UInt8.M &&
            (keyEnd-13).pointee == UInt8.o &&
            (keyEnd-12).pointee == UInt8.d &&
            (keyEnd-11).pointee == UInt8.i &&
            (keyEnd-10).pointee == UInt8.f &&
            (keyEnd-9).pointee == UInt8.i &&
            (keyEnd-8).pointee == UInt8.e &&
            (keyEnd-7).pointee == UInt8.d &&
            (keyEnd-6).pointee == UInt8.minus &&
            (keyEnd-5).pointee == UInt8.S &&
            (keyEnd-4).pointee == UInt8.i &&
            (keyEnd-3).pointee == UInt8.n &&
            (keyEnd-2).pointee == UInt8.c &&
            (keyEnd-1).pointee == UInt8.e {
            ifModifiedSince = HalfHitch(raw: buffer,
                                        count: bufferSize,
                                        from: valueStart - buffer,
                                        to: ptr - buffer)
        }

        if  cookie == nil &&
            size >= 6 &&
            (keyEnd-6).pointee == UInt8.C &&
            (keyEnd-5).pointee == UInt8.o &&
            (keyEnd-4).pointee == UInt8.o &&
            (keyEnd-3).pointee == UInt8.k &&
            (keyEnd-2).pointee == UInt8.i &&
            (keyEnd-1).pointee == UInt8.e {
            cookie = HalfHitch(raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }

        if  expect == nil &&
            size >= 6 &&
            (keyEnd-6).pointee == UInt8.E &&
            (keyEnd-5).pointee == UInt8.x &&
            (keyEnd-4).pointee == UInt8.p &&
            (keyEnd-3).pointee == UInt8.e &&
            (keyEnd-2).pointee == UInt8.c &&
            (keyEnd-1).pointee == UInt8.t {
            expect = HalfHitch(raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }

        if  flynnTag == nil &&
            size >= 9 &&
            (keyEnd-9).pointee == UInt8.F &&
            (keyEnd-8).pointee == UInt8.l &&
            (keyEnd-7).pointee == UInt8.y &&
            (keyEnd-6).pointee == UInt8.n &&
            (keyEnd-5).pointee == UInt8.n &&
            (keyEnd-4).pointee == UInt8.minus &&
            (keyEnd-3).pointee == UInt8.T &&
            (keyEnd-2).pointee == UInt8.a &&
            (keyEnd-1).pointee == UInt8.g {
            flynnTag = HalfHitch(raw: buffer,
                                 count: bufferSize,
                                 from: valueStart - buffer,
                                 to: ptr - buffer)
        }

        if  sessionId == nil &&
            size >= 10 &&
            (keyEnd-10).pointee == UInt8.S &&
            (keyEnd-9).pointee == UInt8.e &&
            (keyEnd-8).pointee == UInt8.s &&
            (keyEnd-7).pointee == UInt8.s &&
            (keyEnd-6).pointee == UInt8.i &&
            (keyEnd-5).pointee == UInt8.o &&
            (keyEnd-4).pointee == UInt8.n &&
            (keyEnd-3).pointee == UInt8.minus &&
            (keyEnd-2).pointee == UInt8.I &&
            (keyEnd-1).pointee == UInt8.d {
            sessionId = HalfHitch(raw: buffer,
                                  count: bufferSize,
                                  from: valueStart - buffer,
                                  to: ptr - buffer)
        }
    }
}
