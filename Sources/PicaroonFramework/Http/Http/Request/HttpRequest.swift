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
    
    public var method: HttpMethod = .UNKNOWN
    
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
    
    public var cookies: [Hitch: Hitch] {
        var _cookies: [Hitch: Hitch] = [:]
        
        if let cookie = cookie {
            // cookie1=something; cookie2=another
            let keyValuePairs: [Hitch] = cookie.components(separatedBy: ";")
            for pair in keyValuePairs {
                let parts: [Hitch] = pair.trim().components(separatedBy: "=")
                if parts.count == 2 {
                    _cookies[parts[0]] = parts[1]
                }
            }
        }
        return _cookies
    }
    
    public init?(request buffer: UnsafeMutablePointer<UInt8>,
                 size bufferSize: Int) {
        guard bufferSize > 6 else { return nil }
                
        let startPtr = buffer
        let endPtr = buffer + bufferSize
        var ptr = startPtr
        var size = ptr - startPtr
        var current: UInt8 = 0
        
        // Handle the first line
        current = ptr.pointee
                                
        if current == .G &&
            (ptr+1).pointee == .E &&
            (ptr+2).pointee == .T &&
            (ptr+3).pointee == .space {
            ptr += 3
            method = .GET
        } else
        if current == .H &&
            (ptr+1).pointee == .E &&
            (ptr+2).pointee == .A &&
            (ptr+3).pointee == .D &&
            (ptr+4).pointee == .space {
            ptr += 4
            method = .HEAD
        } else
        if current == .P &&
            (ptr+1).pointee == .U &&
            (ptr+2).pointee == .T &&
            (ptr+3).pointee == .space {
            ptr += 3
            method = .PUT
        } else
        if current == .P &&
            (ptr+1).pointee == .O &&
            (ptr+2).pointee == .S &&
            (ptr+3).pointee == .T &&
            (ptr+4).pointee == .space {
            ptr += 4
            method = .POST
        } else
        if current == .D &&
            (ptr+1).pointee == .E &&
            (ptr+2).pointee == .L &&
            (ptr+3).pointee == .E &&
            (ptr+4).pointee == .T &&
            (ptr+5).pointee == .E &&
            (ptr+6).pointee == .space {
            ptr += 6
            method = .DELETE
        } else {
            return nil
        }
        
        // We identified the method, now parse the rest of the line
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
            current = ptr.pointee
            
            if urlParametersStartPtr == defaultPtr &&
                (ptr-1).pointee == .questionMark {
                urlParametersStartPtr = ptr
            }
            
            if size >= 4 &&
                (ptr-4).pointee == .s &&
                (ptr-3).pointee == .i &&
                (ptr-2).pointee == .d &&
                (ptr-1).pointee == .equal {
                sessionStartPtr = ptr
            }
            
            if size >= 6 &&
                (ptr-6).pointee == .s &&
                (ptr-5).pointee == .i &&
                (ptr-4).pointee == .d &&
                (ptr-3).pointee == .percentSign &&
                (ptr-2).pointee == .three &&
                ((ptr-1).pointee == .D || (ptr-1).pointee == .d) {
                sessionStartPtr = ptr
            }
            
            if current == .ampersand &&
                sessionStartPtr != defaultPtr {
                sessionEndPtr = ptr
            }
            
            if current == .carriageReturn ||
                current == .newLine ||
                current == .space {
                
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
        
        // Advance to the end of the line
        while ptr < endPtr {
            if (ptr-1).pointee == .carriageReturn && ptr.pointee == .newLine {
                ptr += 1
                break
            }
            ptr += 1
        }
        
        // Every line after the first line
        while ptr < endPtr {
            size = ptr - startPtr
            current = ptr.pointee
            
            // Every line after the header is a Key-Word-No-Space: Whatever Until New Line
            // 1. advance until we find the ":", or a whitespace
            var keyEnd = ptr + 1
            while ptr < endPtr {
                
                if current == .carriageReturn || current == .newLine {
                    while ptr < endPtr && (current == .carriageReturn || current == .newLine) {
                        ptr += 1
                        current = ptr.pointee
                    }
                    // If we reach here, we're at the point we're looking for payload data
                    if let contentLength = contentLength,
                       let contentLengthBytes = contentLength.toInt() {
                        guard endPtr - ptr >= contentLengthBytes else {
                            return nil
                        }
                        content = HalfHitch(raw: buffer,
                                            count: bufferSize,
                                            from: ptr - buffer,
                                            to: (ptr - buffer) + contentLengthBytes)
                    }
                    
                    // Congrats! we have successfully parsed the http request. We now need to bake the request
                    // (ie copy to our own buffer before we pass it along to other people)
                    bake(buffer: buffer,
                         bufferSize: bufferSize)
                    
                    return
                } else if current == .colon {
                    keyEnd = ptr
                    ptr += 1
                    current = ptr.pointee
                    break
                }
                ptr += 1
                current = ptr.pointee
            }
            
            // 2. Skip whitespace
            while ptr < endPtr && (current == .space || current == .tab) {
                ptr += 1
                current = ptr.pointee
            }
            
            let valueStart = ptr
            
            // 3. Advance to the end of the line
            while ptr < endPtr && current != .carriageReturn && current != .newLine {
                ptr += 1
                current = ptr.pointee
            }
            
            // 3. For speed, we only match against the keys we support (no generics)
            parseKeyValue(buffer: buffer,
                          bufferSize: bufferSize,
                          ptr: ptr,
                          valueStart: valueStart,
                          keyEnd: keyEnd)
            
            // Advance to the next line
            if ptr.pointee == .carriageReturn {
                ptr += 1
                if ptr.pointee == .newLine {
                    ptr += 1
                }
            } else if ptr.pointee == .newLine {
                ptr += 1
            } else {
                ptr += 1
            }
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
                if ptr.pointee == .carriageReturn || ptr.pointee == .newLine {
                    while ptr < endPtr && ( ptr.pointee == .carriageReturn ||
                                                ptr.pointee == .newLine) {
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
                if ptr.pointee == .colon {
                    keyEnd = ptr
                    ptr += 1
                    break
                }
                ptr += 1
            }
            
            // 2. Skip whitespace
            while ptr < endPtr && (ptr.pointee == .space || ptr.pointee == .tab) {
                ptr += 1
            }
            
            let valueStart = ptr
            
            // 3. Advance to the end of the line
            while ptr < endPtr && ptr.pointee != .carriageReturn && ptr.pointee != .newLine {
                ptr += 1
            }
            
            // 3. For speed, we only match against the keys we support (no generics)
            parseKeyValue(buffer: buffer,
                          bufferSize: bufferSize,
                          ptr: ptr,
                          valueStart: valueStart,
                          keyEnd: keyEnd)
            
            // Advance to the next line
            if ptr.pointee == .carriageReturn {
                ptr += 1
                if ptr.pointee == .newLine {
                    ptr += 1
                }
            } else if ptr.pointee == .newLine {
                ptr += 1
            }
            
            if ptr.pointee == .newLine {
                lineNumber += 1
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
        
        if host == nil &&
            size >= 5 &&
            (keyEnd-4).pointee == .H &&
            //(keyEnd-3).pointee == .o &&
            (keyEnd-2).pointee == .s &&
            (keyEnd-1).pointee == .t {
            host = HalfHitch(raw: buffer,
                             count: bufferSize,
                             from: valueStart - buffer,
                             to: ptr - buffer)
        }
        
        if userAgent == nil &&
            size >= 10 &&
            (keyEnd-10).pointee == .U &&
            //(keyEnd-9).pointee == .s &&
            (keyEnd-8).pointee == .e &&
            //(keyEnd-7).pointee == .r &&
            (keyEnd-6).pointee == .minus &&
            //(keyEnd-5).pointee == .A &&
            (keyEnd-4).pointee == .g &&
            //(keyEnd-3).pointee == .e &&
            (keyEnd-2).pointee == .n &&
            (keyEnd-1).pointee == .t {
            userAgent = HalfHitch(raw: buffer,
                                  count: bufferSize,
                                  from: valueStart - buffer,
                                  to: ptr - buffer)
        }
        
        if accept == nil &&
            size >= 6 &&
            (keyEnd-6).pointee == .A &&
            //(keyEnd-5).pointee == .c &&
            (keyEnd-4).pointee == .c &&
            //(keyEnd-3).pointee == .e &&
            (keyEnd-2).pointee == .p &&
            (keyEnd-1).pointee == .t {
            accept = HalfHitch(raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if acceptEncoding == nil &&
            size >= 15 &&
            (keyEnd-15).pointee == .A &&
            //(keyEnd-14).pointee == .c &&
            (keyEnd-13).pointee == .c &&
            //(keyEnd-12).pointee == .e &&
            (keyEnd-11).pointee == .p &&
            //(keyEnd-10).pointee == .t &&
            (keyEnd-9).pointee == .minus &&
            //(keyEnd-8).pointee == .E &&
            (keyEnd-7).pointee == .n &&
            //(keyEnd-6).pointee == .c &&
            (keyEnd-5).pointee == .o &&
            //(keyEnd-4).pointee == .d &&
            (keyEnd-3).pointee == .i &&
            //(keyEnd-2).pointee == .n &&
            (keyEnd-1).pointee == .g {
            acceptEncoding = HalfHitch(raw: buffer,
                                       count: bufferSize,
                                       from: valueStart - buffer,
                                       to: ptr - buffer)
        }
        
        if acceptCharset == nil &&
            size >= 14 &&
            (keyEnd-14).pointee == .A &&
            //(keyEnd-13).pointee == .c &&
            (keyEnd-12).pointee == .c &&
            //(keyEnd-11).pointee == .e &&
            (keyEnd-10).pointee == .p &&
            //(keyEnd-9).pointee == .t &&
            (keyEnd-8).pointee == .minus &&
            //(keyEnd-7).pointee == .C &&
            (keyEnd-6).pointee == .h &&
            //(keyEnd-5).pointee == .a &&
            (keyEnd-4).pointee == .r &&
            //(keyEnd-3).pointee == .s &&
            (keyEnd-2).pointee == .e &&
            (keyEnd-1).pointee == .t {
            acceptCharset = HalfHitch(raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if acceptLanguage == nil &&
            size >= 15 &&
            (keyEnd-15).pointee == .A &&
            //(keyEnd-14).pointee == .c &&
            (keyEnd-13).pointee == .c &&
            //(keyEnd-12).pointee == .e &&
            (keyEnd-11).pointee == .p &&
            //(keyEnd-10).pointee == .t &&
            (keyEnd-9).pointee == .minus &&
            //(keyEnd-8).pointee == .L &&
            (keyEnd-7).pointee == .a &&
            //(keyEnd-6).pointee == .n &&
            (keyEnd-5).pointee == .g &&
            //(keyEnd-4).pointee == .u &&
            (keyEnd-3).pointee == .a &&
            //(keyEnd-2).pointee == .g &&
            (keyEnd-1).pointee == .e {
            acceptLanguage = HalfHitch(raw: buffer,
                                       count: bufferSize,
                                       from: valueStart - buffer,
                                       to: ptr - buffer)
        }
        
        if connection == nil &&
            size >= 10 &&
            (keyEnd-10).pointee == .C &&
            //(keyEnd-9).pointee == .o &&
            (keyEnd-8).pointee == .n &&
            //(keyEnd-7).pointee == .n &&
            (keyEnd-6).pointee == .e &&
            //(keyEnd-5).pointee == .c &&
            (keyEnd-4).pointee == .t &&
            //(keyEnd-3).pointee == .i &&
            (keyEnd-2).pointee == .o &&
            (keyEnd-1).pointee == .n {
            connection = HalfHitch(raw: buffer,
                                   count: bufferSize,
                                   from: valueStart - buffer,
                                   to: ptr - buffer)
        }
        
        if upgradeInsecureRequests == nil &&
            size >= 25 &&
            (keyEnd-25).pointee == .U &&
            //(keyEnd-24).pointee == .p &&
            (keyEnd-23).pointee == .g &&
            //(keyEnd-22).pointee == .r &&
            (keyEnd-21).pointee == .a &&
            //(keyEnd-20).pointee == .d &&
            (keyEnd-19).pointee == .e &&
            //(keyEnd-18).pointee == .minus &&
            (keyEnd-17).pointee == .I &&
            //(keyEnd-16).pointee == .n &&
            (keyEnd-15).pointee == .s &&
            //(keyEnd-14).pointee == .e &&
            (keyEnd-13).pointee == .c &&
            //(keyEnd-12).pointee == .u &&
            (keyEnd-11).pointee == .r &&
            //(keyEnd-10).pointee == .e &&
            (keyEnd-9).pointee == .minus &&
            //(keyEnd-8).pointee == .R &&
            (keyEnd-7).pointee == .e &&
            //(keyEnd-6).pointee == .q &&
            (keyEnd-5).pointee == .u &&
            //(keyEnd-4).pointee == .e &&
            (keyEnd-3).pointee == .s &&
            //(keyEnd-2).pointee == .t &&
            (keyEnd-1).pointee == .s {
            upgradeInsecureRequests = HalfHitch(raw: buffer,
                                                count: bufferSize,
                                                from: valueStart - buffer,
                                                to: ptr - buffer)
        }
        
        if contentLength == nil &&
            size >= 14 &&
            (keyEnd-14).pointee == .C &&
            //(keyEnd-13).pointee == .o &&
            (keyEnd-12).pointee == .n &&
            //(keyEnd-11).pointee == .t &&
            (keyEnd-10).pointee == .e &&
            //(keyEnd-9).pointee == .n &&
            (keyEnd-8).pointee == .t &&
            //(keyEnd-7).pointee == .minus &&
            (keyEnd-6).pointee == .L &&
            //(keyEnd-5).pointee == .e &&
            (keyEnd-4).pointee == .n &&
            //(keyEnd-3).pointee == .g &&
            (keyEnd-2).pointee == .t &&
            (keyEnd-1).pointee == .h {
            contentLength = HalfHitch(raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if contentType == nil &&
            size >= 12 &&
            (keyEnd-12).pointee == .C &&
            //(keyEnd-11).pointee == .o &&
            (keyEnd-10).pointee == .n &&
            //(keyEnd-9).pointee == .t &&
            (keyEnd-8).pointee == .e &&
            //(keyEnd-7).pointee == .n &&
            (keyEnd-6).pointee == .t &&
            //(keyEnd-5).pointee == .minus &&
            (keyEnd-4).pointee == .T &&
            //(keyEnd-3).pointee == .y &&
            (keyEnd-2).pointee == .p &&
            (keyEnd-1).pointee == .e {
            contentType = HalfHitch(raw: buffer,
                                    count: bufferSize,
                                    from: valueStart - buffer,
                                    to: ptr - buffer)
        }
        
        if contentDisposition == nil &&
            size >= 19 &&
            (keyEnd-19).pointee == .C &&
            //(keyEnd-18).pointee == .o &&
            (keyEnd-17).pointee == .n &&
            //(keyEnd-16).pointee == .t &&
            (keyEnd-15).pointee == .e &&
            //(keyEnd-14).pointee == .n &&
            (keyEnd-13).pointee == .t &&
            //(keyEnd-12).pointee == .minus &&
            (keyEnd-11).pointee == .D &&
            //(keyEnd-10).pointee == .i &&
            (keyEnd-9).pointee == .s &&
            //(keyEnd-8).pointee == .p &&
            (keyEnd-7).pointee == .o &&
            //(keyEnd-6).pointee == .s &&
            (keyEnd-5).pointee == .i &&
            //(keyEnd-4).pointee == .t &&
            (keyEnd-3).pointee == .i &&
            //(keyEnd-2).pointee == .o &&
            (keyEnd-1).pointee == .n {
            contentDisposition = HalfHitch(raw: buffer,
                                           count: bufferSize,
                                           from: valueStart - buffer,
                                           to: ptr - buffer)
        }
        
        if ifModifiedSince == nil &&
            size >= 17 &&
            (keyEnd-17).pointee == .I &&
            //(keyEnd-16).pointee == .f &&
            (keyEnd-15).pointee == .minus &&
            //(keyEnd-14).pointee == .M &&
            (keyEnd-13).pointee == .o &&
            //(keyEnd-12).pointee == .d &&
            (keyEnd-11).pointee == .i &&
            //(keyEnd-10).pointee == .f &&
            (keyEnd-9).pointee == .i &&
            //(keyEnd-8).pointee == .e &&
            (keyEnd-7).pointee == .d &&
            //(keyEnd-6).pointee == .minus &&
            (keyEnd-5).pointee == .S &&
            //(keyEnd-4).pointee == .i &&
            (keyEnd-3).pointee == .n &&
            //(keyEnd-2).pointee == .c &&
            (keyEnd-1).pointee == .e {
            ifModifiedSince = HalfHitch(raw: buffer,
                                        count: bufferSize,
                                        from: valueStart - buffer,
                                        to: ptr - buffer)
        }
        
        if cookie == nil &&
            size >= 6 &&
            (keyEnd-6).pointee == .C &&
            //(keyEnd-5).pointee == .o &&
            (keyEnd-4).pointee == .o &&
            //(keyEnd-3).pointee == .k &&
            (keyEnd-2).pointee == .i &&
            (keyEnd-1).pointee == .e {
            cookie = HalfHitch(raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if expect == nil &&
            size >= 6 &&
            (keyEnd-6).pointee == .E &&
            //(keyEnd-5).pointee == .x &&
            (keyEnd-4).pointee == .p &&
            //(keyEnd-3).pointee == .e &&
            (keyEnd-2).pointee == .c &&
            (keyEnd-1).pointee == .t {
            expect = HalfHitch(raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if flynnTag == nil &&
            size >= 9 &&
            (keyEnd-9).pointee == .F &&
            //(keyEnd-8).pointee == .l &&
            (keyEnd-7).pointee == .y &&
            //(keyEnd-6).pointee == .n &&
            (keyEnd-5).pointee == .n &&
            //(keyEnd-4).pointee == .minus &&
            (keyEnd-3).pointee == .T &&
            //(keyEnd-2).pointee == .a &&
            (keyEnd-1).pointee == .g {
            flynnTag = HalfHitch(raw: buffer,
                                 count: bufferSize,
                                 from: valueStart - buffer,
                                 to: ptr - buffer)
        }
        
        if sessionId == nil &&
            size >= 10 &&
            (keyEnd-10).pointee == .S &&
            //(keyEnd-9).pointee == .e &&
            (keyEnd-8).pointee == .s &&
            //(keyEnd-7).pointee == .s &&
            (keyEnd-6).pointee == .i &&
            //(keyEnd-5).pointee == .o &&
            (keyEnd-4).pointee == .n &&
            //(keyEnd-3).pointee == .minus &&
            (keyEnd-2).pointee == .I &&
            (keyEnd-1).pointee == .d {
            sessionId = HalfHitch(raw: buffer,
                                  count: bufferSize,
                                  from: valueStart - buffer,
                                  to: ptr - buffer)
        }
    }
}
