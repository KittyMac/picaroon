import Flynn
import Foundation
import Socket

// swiftlint:disable function_body_length
// swiftlint:disable cyclomatic_complexity
// swiftlint:disable identifier_name
// swiftlint:disable type_body_length

public struct HttpRequest {
    public var method: HttpMethod?

    @InMemory public var url: String?
    @InMemory public var host: String?
    @InMemory public var userAgent: String?
    @InMemory public var accept: String?
    @InMemory public var acceptEncoding: String?
    @InMemory public var acceptCharset: String?
    @InMemory public var acceptLanguage: String?
    @InMemory public var connection: String?
    @InMemory public var upgradeInsecureRequests: String?
    @InMemory public var contentLength: String?
    @InMemory public var ifModifiedSince: String?
    @InMemory public var cookie: String?
    @InMemory public var expect: String?
    @InMemory public var flynnTag: String?

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

    public init(_ buffer: UnsafeMutablePointer<CChar>, _ bufferSize: Int) {

        let startPtr = buffer
        let endPtr = buffer + bufferSize

        var ptr = startPtr + 3

        var lineNumber = 0

        incomplete = true

        while ptr < endPtr {
            if lineNumber == 0 {
                if method == nil {
                    if  (ptr-3).pointee == CChar.G &&
                        (ptr-2).pointee == CChar.E &&
                        (ptr-1).pointee == CChar.T &&
                        ptr.pointee == CChar.space {
                        method = .GET
                    } else if
                        (ptr-4).pointee == CChar.H &&
                        (ptr-3).pointee == CChar.E &&
                        (ptr-2).pointee == CChar.A &&
                        (ptr-1).pointee == CChar.D &&
                        ptr.pointee == CChar.space {
                        method = .HEAD
                    } else if
                        (ptr-3).pointee == CChar.P &&
                        (ptr-2).pointee == CChar.U &&
                        (ptr-1).pointee == CChar.T &&
                        ptr.pointee == CChar.space {
                        method = .PUT
                    } else if
                        (ptr-4).pointee == CChar.P &&
                        (ptr-3).pointee == CChar.O &&
                        (ptr-2).pointee == CChar.S &&
                        (ptr-1).pointee == CChar.T &&
                        ptr.pointee == CChar.space {
                        method = .POST
                    } else if
                        (ptr-6).pointee == CChar.D &&
                        (ptr-5).pointee == CChar.E &&
                        (ptr-4).pointee == CChar.L &&
                        (ptr-3).pointee == CChar.E &&
                        (ptr-2).pointee == CChar.T &&
                        (ptr-1).pointee == CChar.E &&
                        ptr.pointee == CChar.space {
                        method = .DELETE
                    }

                    // We identified the method, now parse the rest of the line
                    if method != nil {
                        let urlStartPtr = ptr + 1
                        var urlEndPtr = ptr + 1
                        while ptr < endPtr {
                            if ptr.pointee == CChar.carriageReturn || ptr.pointee == CChar.newLine {
                                break
                            }
                            if ptr.pointee == CChar.space {
                                urlEndPtr = ptr
                            }
                            ptr += 1
                        }
                        $url = InMemory(initialValue: nil, urlStartPtr, urlEndPtr)
                    }
                }
            } else {
                // Every line after the header is a Key-Word-No-Space: Whatever Until New Line
                // 1. advance until we find the ":", or a whitespace
                var keyEnd = ptr + 1
                while ptr < endPtr {
                    if ptr.pointee == CChar.carriageReturn || ptr.pointee == CChar.newLine {
                        while ptr < endPtr && ( ptr.pointee == CChar.carriageReturn ||
                                                ptr.pointee == CChar.newLine) {
                            ptr += 1
                        }
                        // If we reach here, we're at the point we're looking for payload data
                        if let contentLength = contentLength {
                            if let contentLengthBytes = Int(contentLength) {
                                if endPtr - ptr >= contentLengthBytes {
                                    content = Data(bytes: ptr, count: contentLengthBytes)
                                    incomplete = false
                                }
                            }
                        } else {
                            incomplete = false
                        }
                        return
                    }
                    if ptr.pointee == CChar.colon {
                        keyEnd = ptr
                        ptr += 1
                        break
                    }
                    ptr += 1
                }

                // 2. Skip whitespace
                while ptr < endPtr && (ptr.pointee == CChar.space || ptr.pointee == CChar.tab) {
                    ptr += 1
                }

                let valueStart = ptr

                // 3. Advance to the end of the line
                while ptr < endPtr && ptr.pointee != CChar.carriageReturn && ptr.pointee != CChar.newLine {
                    ptr += 1
                }

                // 3. For speed, we only match against the keys we support (no generics)
                if  $host.isEmpty() &&
                    (keyEnd-4).pointee == CChar.H &&
                    (keyEnd-3).pointee == CChar.o &&
                    (keyEnd-2).pointee == CChar.s &&
                    (keyEnd-1).pointee == CChar.t {
                    $host = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $userAgent.isEmpty() &&
                    (keyEnd-10).pointee == CChar.U &&
                    (keyEnd-9).pointee == CChar.s &&
                    (keyEnd-8).pointee == CChar.e &&
                    (keyEnd-7).pointee == CChar.r &&
                    (keyEnd-6).pointee == CChar.minus &&
                    (keyEnd-5).pointee == CChar.A &&
                    (keyEnd-4).pointee == CChar.g &&
                    (keyEnd-3).pointee == CChar.e &&
                    (keyEnd-2).pointee == CChar.n &&
                    (keyEnd-1).pointee == CChar.t {
                    $userAgent = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $accept.isEmpty() &&
                    (keyEnd-6).pointee == CChar.A &&
                    (keyEnd-5).pointee == CChar.c &&
                    (keyEnd-4).pointee == CChar.c &&
                    (keyEnd-3).pointee == CChar.e &&
                    (keyEnd-2).pointee == CChar.p &&
                    (keyEnd-1).pointee == CChar.t {
                    $accept = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $acceptEncoding.isEmpty() &&
                    (keyEnd-15).pointee == CChar.A &&
                    (keyEnd-14).pointee == CChar.c &&
                    (keyEnd-13).pointee == CChar.c &&
                    (keyEnd-12).pointee == CChar.e &&
                    (keyEnd-11).pointee == CChar.p &&
                    (keyEnd-10).pointee == CChar.t &&
                    (keyEnd-9).pointee == CChar.minus &&
                    (keyEnd-8).pointee == CChar.E &&
                    (keyEnd-7).pointee == CChar.n &&
                    (keyEnd-6).pointee == CChar.c &&
                    (keyEnd-5).pointee == CChar.o &&
                    (keyEnd-4).pointee == CChar.d &&
                    (keyEnd-3).pointee == CChar.i &&
                    (keyEnd-2).pointee == CChar.n &&
                    (keyEnd-1).pointee == CChar.g {
                    $acceptEncoding = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $acceptCharset.isEmpty() &&
                    (keyEnd-14).pointee == CChar.A &&
                    (keyEnd-13).pointee == CChar.c &&
                    (keyEnd-12).pointee == CChar.c &&
                    (keyEnd-11).pointee == CChar.e &&
                    (keyEnd-10).pointee == CChar.p &&
                    (keyEnd-9).pointee == CChar.t &&
                    (keyEnd-8).pointee == CChar.minus &&
                    (keyEnd-7).pointee == CChar.C &&
                    (keyEnd-6).pointee == CChar.h &&
                    (keyEnd-5).pointee == CChar.a &&
                    (keyEnd-4).pointee == CChar.r &&
                    (keyEnd-3).pointee == CChar.s &&
                    (keyEnd-2).pointee == CChar.e &&
                    (keyEnd-1).pointee == CChar.t {
                    $acceptCharset = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $acceptLanguage.isEmpty() &&
                    (keyEnd-15).pointee == CChar.A &&
                    (keyEnd-14).pointee == CChar.c &&
                    (keyEnd-13).pointee == CChar.c &&
                    (keyEnd-12).pointee == CChar.e &&
                    (keyEnd-11).pointee == CChar.p &&
                    (keyEnd-10).pointee == CChar.t &&
                    (keyEnd-9).pointee == CChar.minus &&
                    (keyEnd-8).pointee == CChar.L &&
                    (keyEnd-7).pointee == CChar.a &&
                    (keyEnd-6).pointee == CChar.n &&
                    (keyEnd-5).pointee == CChar.g &&
                    (keyEnd-4).pointee == CChar.u &&
                    (keyEnd-3).pointee == CChar.a &&
                    (keyEnd-2).pointee == CChar.g &&
                    (keyEnd-1).pointee == CChar.e {
                    $acceptLanguage = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $connection.isEmpty() &&
                    (keyEnd-10).pointee == CChar.C &&
                    (keyEnd-9).pointee == CChar.o &&
                    (keyEnd-8).pointee == CChar.n &&
                    (keyEnd-7).pointee == CChar.n &&
                    (keyEnd-6).pointee == CChar.e &&
                    (keyEnd-5).pointee == CChar.c &&
                    (keyEnd-4).pointee == CChar.t &&
                    (keyEnd-3).pointee == CChar.i &&
                    (keyEnd-2).pointee == CChar.o &&
                    (keyEnd-1).pointee == CChar.n {
                    $connection = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $upgradeInsecureRequests.isEmpty() &&
                    (keyEnd-25).pointee == CChar.U &&
                    (keyEnd-24).pointee == CChar.p &&
                    (keyEnd-23).pointee == CChar.g &&
                    (keyEnd-22).pointee == CChar.r &&
                    (keyEnd-21).pointee == CChar.a &&
                    (keyEnd-20).pointee == CChar.d &&
                    (keyEnd-19).pointee == CChar.e &&
                    (keyEnd-18).pointee == CChar.minus &&
                    (keyEnd-17).pointee == CChar.I &&
                    (keyEnd-16).pointee == CChar.n &&
                    (keyEnd-15).pointee == CChar.s &&
                    (keyEnd-14).pointee == CChar.e &&
                    (keyEnd-13).pointee == CChar.c &&
                    (keyEnd-12).pointee == CChar.u &&
                    (keyEnd-11).pointee == CChar.r &&
                    (keyEnd-10).pointee == CChar.e &&
                    (keyEnd-9).pointee == CChar.minus &&
                    (keyEnd-8).pointee == CChar.R &&
                    (keyEnd-7).pointee == CChar.e &&
                    (keyEnd-6).pointee == CChar.q &&
                    (keyEnd-5).pointee == CChar.u &&
                    (keyEnd-4).pointee == CChar.e &&
                    (keyEnd-3).pointee == CChar.s &&
                    (keyEnd-2).pointee == CChar.t &&
                    (keyEnd-1).pointee == CChar.s {
                    $upgradeInsecureRequests = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $contentLength.isEmpty() &&
                    (keyEnd-14).pointee == CChar.C &&
                    (keyEnd-13).pointee == CChar.o &&
                    (keyEnd-12).pointee == CChar.n &&
                    (keyEnd-11).pointee == CChar.t &&
                    (keyEnd-10).pointee == CChar.e &&
                    (keyEnd-9).pointee == CChar.n &&
                    (keyEnd-8).pointee == CChar.t &&
                    (keyEnd-7).pointee == CChar.minus &&
                    (keyEnd-6).pointee == CChar.L &&
                    (keyEnd-5).pointee == CChar.e &&
                    (keyEnd-4).pointee == CChar.n &&
                    (keyEnd-3).pointee == CChar.g &&
                    (keyEnd-2).pointee == CChar.t &&
                    (keyEnd-1).pointee == CChar.h {
                    $contentLength = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $ifModifiedSince.isEmpty() &&
                    (keyEnd-17).pointee == CChar.I &&
                    (keyEnd-16).pointee == CChar.f &&
                    (keyEnd-15).pointee == CChar.minus &&
                    (keyEnd-14).pointee == CChar.M &&
                    (keyEnd-13).pointee == CChar.o &&
                    (keyEnd-12).pointee == CChar.d &&
                    (keyEnd-11).pointee == CChar.i &&
                    (keyEnd-10).pointee == CChar.f &&
                    (keyEnd-9).pointee == CChar.i &&
                    (keyEnd-8).pointee == CChar.e &&
                    (keyEnd-7).pointee == CChar.d &&
                    (keyEnd-6).pointee == CChar.minus &&
                    (keyEnd-5).pointee == CChar.S &&
                    (keyEnd-4).pointee == CChar.i &&
                    (keyEnd-3).pointee == CChar.n &&
                    (keyEnd-2).pointee == CChar.c &&
                    (keyEnd-1).pointee == CChar.e {
                    $ifModifiedSince = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $cookie.isEmpty() &&
                    (keyEnd-6).pointee == CChar.C &&
                    (keyEnd-5).pointee == CChar.o &&
                    (keyEnd-4).pointee == CChar.o &&
                    (keyEnd-3).pointee == CChar.k &&
                    (keyEnd-2).pointee == CChar.i &&
                    (keyEnd-1).pointee == CChar.e {
                    $cookie = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $expect.isEmpty() &&
                    (keyEnd-6).pointee == CChar.E &&
                    (keyEnd-5).pointee == CChar.x &&
                    (keyEnd-4).pointee == CChar.p &&
                    (keyEnd-3).pointee == CChar.e &&
                    (keyEnd-2).pointee == CChar.c &&
                    (keyEnd-1).pointee == CChar.t {
                    $expect = InMemory(initialValue: nil, valueStart, ptr)
                }

                if  $flynnTag.isEmpty() &&
                    (keyEnd-9).pointee == CChar.F &&
                    (keyEnd-8).pointee == CChar.l &&
                    (keyEnd-7).pointee == CChar.y &&
                    (keyEnd-6).pointee == CChar.n &&
                    (keyEnd-5).pointee == CChar.n &&
                    (keyEnd-4).pointee == CChar.minus &&
                    (keyEnd-3).pointee == CChar.T &&
                    (keyEnd-2).pointee == CChar.a &&
                    (keyEnd-1).pointee == CChar.g {
                    $flynnTag = InMemory(initialValue: nil, valueStart, ptr)
                }

                // Advance to the next line
                if ptr.pointee == CChar.carriageReturn {
                    ptr += 1
                    if ptr.pointee == CChar.newLine {
                        ptr += 1
                    }
                } else if ptr.pointee == CChar.newLine {
                    ptr += 1
                }
            }

            if ptr.pointee == CChar.newLine {
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

}
