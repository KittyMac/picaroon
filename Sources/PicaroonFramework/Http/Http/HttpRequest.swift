import Flynn
import Foundation

// swiftlint:disable function_body_length
// swiftlint:disable cyclomatic_complexity
// swiftlint:disable identifier_name
// swiftlint:disable type_body_length
// swiftlint:disable file_length

public class HttpRequest {
    public var method: HttpMethod?

    @InMemory public var url: String?
    @InMemory public var urlParameters: String?
    @InMemory public var host: String?
    @InMemory public var userAgent: String?
    @InMemory public var accept: String?
    @InMemory public var acceptEncoding: String?
    @InMemory public var acceptCharset: String?
    @InMemory public var acceptLanguage: String?
    @InMemory public var connection: String?
    @InMemory public var upgradeInsecureRequests: String?
    @InMemory public var contentLength: String?
    @InMemory public var contentType: String?
    @InMemory public var contentDisposition: String?
    @InMemory public var ifModifiedSince: String?
    @InMemory public var cookie: String?
    @InMemory public var expect: String?
    @InMemory public var flynnTag: String?
    @InMemory public var sessionId: String?
    @InMemory public var sid: String?

    private var parameters: [String: String]?
    public func parameter(name: String) -> String? {
        if let parameters = parameters {
            return parameters[name]
        }

        guard let urlParameters = urlParameters else { return nil }
        guard let url = URL(string: "https://www.a.com/b?\(urlParameters)") else { return nil }

        parameters = [:]

        if let components = URLComponents(url: url,
                                          resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            for item in items {
                parameters?[item.name] = item.value
            }
            return parameters?[name]
        }
        return nil
    }

    private var internalBuffer: UnsafeMutablePointer<UInt8>?

    private func bake(buffer: UnsafePointer<UInt8>,
                      size bufferSize: Int) {

        internalBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

        if let internalBuffer = internalBuffer {
            internalBuffer.assign(from: buffer, count: bufferSize)

            $url.bufferPtr = UnsafePointer(internalBuffer)
            $urlParameters.bufferPtr = UnsafePointer(internalBuffer)
            $host.bufferPtr = UnsafePointer(internalBuffer)
            $userAgent.bufferPtr = UnsafePointer(internalBuffer)
            $accept.bufferPtr = UnsafePointer(internalBuffer)
            $acceptEncoding.bufferPtr = UnsafePointer(internalBuffer)
            $acceptCharset.bufferPtr = UnsafePointer(internalBuffer)
            $acceptLanguage.bufferPtr = UnsafePointer(internalBuffer)
            $connection.bufferPtr = UnsafePointer(internalBuffer)
            $upgradeInsecureRequests.bufferPtr = UnsafePointer(internalBuffer)
            $contentLength.bufferPtr = UnsafePointer(internalBuffer)
            $contentType.bufferPtr = UnsafePointer(internalBuffer)
            $contentDisposition.bufferPtr = UnsafePointer(internalBuffer)
            $ifModifiedSince.bufferPtr = UnsafePointer(internalBuffer)
            $cookie.bufferPtr = UnsafePointer(internalBuffer)
            $expect.bufferPtr = UnsafePointer(internalBuffer)
            $flynnTag.bufferPtr = UnsafePointer(internalBuffer)
            $sessionId.bufferPtr = UnsafePointer(internalBuffer)
        }
    }

    deinit {
        if let internalBuffer = internalBuffer {
            internalBuffer.deallocate()
        }
    }

    public var cookies: [String: String] {
        var _cookies: [String: String] = [:]

        if let cookie = cookie {
            // cookie1=something; cookie2=another
            let keyValuePairs = cookie.components(separatedBy: ";")
            for pair in keyValuePairs {
                let parts = pair.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "=")
                if parts.count == 2 {
                    _cookies[parts[0]] = parts[1]
                }
            }
        }
        return _cookies
    }

    public var content: Data?

    public var incomplete: Bool

    public init() {
        incomplete = true
    }

    public convenience init(request unsafeRawBufferPointer: UnsafeRawBufferPointer,
                            size bufferSize: Int) {
        let unsafeBufferPointer = unsafeRawBufferPointer.bindMemory(to: UInt8.self)
        guard let buffer = unsafeBufferPointer.baseAddress else {
            self.init()
            return
        }
        self.init(request: buffer, size: bufferSize)
    }

    public init(request buffer: UnsafePointer<UInt8>,
                size bufferSize: Int) {

        let startPtr = buffer
        let endPtr = buffer + bufferSize

        var ptr = startPtr + 3

        var lineNumber = 0

        incomplete = true

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
                        $url = InMemory(initialValue: nil,
                                        buffer,
                                        urlStartPtr - buffer,
                                        urlEndPtr - buffer)

                        if sessionStartPtr < sessionEndPtr {
                            $sid = InMemory(initialValue: nil,
                                            buffer,
                                            sessionStartPtr - buffer,
                                            sessionEndPtr - buffer)
                        }
                        if urlParametersStartPtr < urlParametersEndPtr {
                            $urlParameters = InMemory(initialValue: nil,
                                                      buffer,
                                                      urlParametersStartPtr - buffer,
                                                      urlParametersEndPtr - buffer)
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
                            if let contentLengthBytes = Int(contentLength) {
                                if endPtr - ptr >= contentLengthBytes {
                                    content = Data(bytes: ptr, count: contentLengthBytes)
                                    incomplete = false
                                    bake(buffer: buffer, size: ptr - buffer)
                                }
                            }
                        } else {
                            incomplete = false
                            bake(buffer: buffer, size: ptr - buffer)
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
    }

    public init(multipart buffer: UnsafePointer<UInt8>, size bufferSize: Int) {

        let startPtr = buffer
        let endPtr = buffer + bufferSize

        var ptr = startPtr + 3

        var lineNumber = 0

        incomplete = false

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
                        content = Data(bytes: ptr, count: endPtr - ptr)
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
    }

    @inline(__always)
    private func parseKeyValue(buffer: UnsafePointer<UInt8>,
                               ptr: UnsafePointer<UInt8>,
                               valueStart: UnsafePointer<UInt8>,
                               keyEnd: UnsafePointer<UInt8>) {
        let size = keyEnd - buffer

        if  $host.isEmpty() &&
            size >= 5 &&
            (keyEnd-4).pointee == UInt8.H &&
            (keyEnd-3).pointee == UInt8.o &&
            (keyEnd-2).pointee == UInt8.s &&
            (keyEnd-1).pointee == UInt8.t {
            $host = InMemory(initialValue: nil,
                             buffer,
                             valueStart - buffer,
                             ptr - buffer)
        }

        if  $userAgent.isEmpty() &&
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
            $userAgent = InMemory(initialValue: nil,
                                  buffer,
                                  valueStart - buffer,
                                  ptr - buffer)
        }

        if  $accept.isEmpty() &&
            size >= 6 &&
            (keyEnd-6).pointee == UInt8.A &&
            (keyEnd-5).pointee == UInt8.c &&
            (keyEnd-4).pointee == UInt8.c &&
            (keyEnd-3).pointee == UInt8.e &&
            (keyEnd-2).pointee == UInt8.p &&
            (keyEnd-1).pointee == UInt8.t {
            $accept = InMemory(initialValue: nil,
                               buffer,
                               valueStart - buffer,
                               ptr - buffer)
        }

        if  $acceptEncoding.isEmpty() &&
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
            $acceptEncoding = InMemory(initialValue: nil,
                                       buffer,
                                       valueStart - buffer,
                                       ptr - buffer)
        }

        if  $acceptCharset.isEmpty() &&
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
            $acceptCharset = InMemory(initialValue: nil,
                                      buffer,
                                      valueStart - buffer,
                                      ptr - buffer)
        }

        if  $acceptLanguage.isEmpty() &&
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
            $acceptLanguage = InMemory(initialValue: nil,
                                       buffer,
                                       valueStart - buffer,
                                       ptr - buffer)
        }

        if  $connection.isEmpty() &&
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
            $connection = InMemory(initialValue: nil,
                                   buffer,
                                   valueStart - buffer,
                                   ptr - buffer)
        }

        if  $upgradeInsecureRequests.isEmpty() &&
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
            $upgradeInsecureRequests = InMemory(initialValue: nil,
                                                buffer,
                                                valueStart - buffer,
                                                ptr - buffer)
        }

        if  $contentLength.isEmpty() &&
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
            $contentLength = InMemory(initialValue: nil,
                                      buffer,
                                      valueStart - buffer,
                                      ptr - buffer)
        }

        if  $contentType.isEmpty() &&
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
            $contentType = InMemory(initialValue: nil,
                                    buffer,
                                    valueStart - buffer,
                                    ptr - buffer)
        }

        if  $contentDisposition.isEmpty() &&
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
            $contentDisposition = InMemory(initialValue: nil,
                                           buffer,
                                           valueStart - buffer,
                                           ptr - buffer)
        }

        if  $ifModifiedSince.isEmpty() &&
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
            $ifModifiedSince = InMemory(initialValue: nil,
                                        buffer,
                                        valueStart - buffer,
                                        ptr - buffer)
        }

        if  $cookie.isEmpty() &&
            size >= 6 &&
            (keyEnd-6).pointee == UInt8.C &&
            (keyEnd-5).pointee == UInt8.o &&
            (keyEnd-4).pointee == UInt8.o &&
            (keyEnd-3).pointee == UInt8.k &&
            (keyEnd-2).pointee == UInt8.i &&
            (keyEnd-1).pointee == UInt8.e {
            $cookie = InMemory(initialValue: nil,
                               buffer,
                               valueStart - buffer,
                               ptr - buffer)
        }

        if  $expect.isEmpty() &&
            size >= 6 &&
            (keyEnd-6).pointee == UInt8.E &&
            (keyEnd-5).pointee == UInt8.x &&
            (keyEnd-4).pointee == UInt8.p &&
            (keyEnd-3).pointee == UInt8.e &&
            (keyEnd-2).pointee == UInt8.c &&
            (keyEnd-1).pointee == UInt8.t {
            $expect = InMemory(initialValue: nil,
                               buffer,
                               valueStart - buffer,
                               ptr - buffer)
        }

        if  $flynnTag.isEmpty() &&
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
            $flynnTag = InMemory(initialValue: nil,
                                 buffer,
                                 valueStart - buffer,
                                 ptr - buffer)
        }

        if  $sessionId.isEmpty() &&
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
            $sessionId = InMemory(initialValue: nil,
                                  buffer,
                                  valueStart - buffer,
                                  ptr - buffer)
        }

    }
}
