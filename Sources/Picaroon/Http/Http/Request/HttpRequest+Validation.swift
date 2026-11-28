import Foundation
import Hitch

private let asciiSpace: UInt8 = 0x20
private let asciiTab: UInt8 = 0x09
private let asciiCR: UInt8 = 0x0D
private let asciiLF: UInt8 = 0x0A
private let asciiColon: UInt8 = 0x3A
private let asciiZero: UInt8 = 0x30
private let asciiNine: UInt8 = 0x39
private let asciiUpperA: UInt8 = 0x41
private let asciiUpperZ: UInt8 = 0x5A

private let supportedMethods: [[UInt8]] = ["GET", "HEAD", "PUT", "POST", "DELETE"].map { Array($0.utf8) }
private let contentLengthName: [UInt8] = Array("content-length".utf8)
private let transferEncodingName: [UInt8] = Array("transfer-encoding".utf8)

/// Longest method token scanned before the request line is declared invalid.
private let maxMethodLength = 16

extension HttpRequest {

    /// Decides whether the bytes received so far can never become a request Picaroon will serve.
    ///
    /// `HttpRequest.init?` returns nil both for "incomplete, wait for more bytes" and for "this will
    /// never parse"; the connection cannot tell the two apart and would otherwise wait forever on the
    /// second. Call this first: it returns nil when the request is valid or simply incomplete (keep
    /// reading), and otherwise the status to answer with before closing the connection.
    public static func validate(config: ServerConfig,
                                request buffer: UnsafePointer<UInt8>,
                                size: Int) -> HttpStatus? {
        guard size > 0 else { return nil }

        // 1. Method token: uppercase ASCII letters terminated by a single space.
        var idx = 0
        while idx < size {
            let c = buffer[idx]
            if c == asciiSpace { break }
            guard c >= asciiUpperA && c <= asciiUpperZ else { return .badRequest }
            idx += 1
            if idx > maxMethodLength { return .badRequest }
        }
        guard idx < size else { return nil }          // method still arriving
        guard idx > 0 else { return .badRequest }     // request line starts with a space

        let isSupported = supportedMethods.contains { method in
            guard method.count == idx else { return false }
            for i in 0..<idx where method[i] != buffer[i] { return false }
            return true
        }
        guard isSupported else { return .notImplemented }

        // 2. Wait for the complete header block (terminated by CRLF CRLF) before judging headers.
        var lineStart = -1
        var scan = idx
        while scan + 1 < size {
            if buffer[scan] == asciiCR && buffer[scan + 1] == asciiLF {
                lineStart = scan + 2
                break
            }
            scan += 1
        }
        guard lineStart >= 0 else { return nil }      // request line still arriving

        var contentLength: Int? = nil

        while true {
            // find the end of this header line
            var lineEnd = lineStart
            while lineEnd + 1 < size && !(buffer[lineEnd] == asciiCR && buffer[lineEnd + 1] == asciiLF) {
                lineEnd += 1
            }
            guard lineEnd + 1 < size else { return nil }   // headers still arriving

            // empty line: end of the header block
            if lineEnd == lineStart {
                let headerBytes = lineEnd + 2
                if let contentLength = contentLength,
                   contentLength > config.maxRequestInBytes - headerBytes {
                    return .requestTooLarge
                }
                return nil
            }

            // every header line must be "name: value"
            var colon = lineStart
            while colon < lineEnd && buffer[colon] != asciiColon {
                colon += 1
            }
            guard colon < lineEnd, colon > lineStart else { return .badRequest }

            if matches(buffer, from: lineStart, to: colon, name: contentLengthName) {
                guard let value = parseDecimal(buffer, from: colon + 1, to: lineEnd) else {
                    return .badRequest
                }
                // conflicting duplicate Content-Length headers are a request smuggling signal
                if let previous = contentLength, previous != value {
                    return .badRequest
                }
                contentLength = value
            } else if matches(buffer, from: lineStart, to: colon, name: transferEncodingName) {
                // Picaroon only reads bodies delimited by Content-Length
                return .notImplemented
            }

            lineStart = lineEnd + 2
        }
    }

    private static func matches(_ buffer: UnsafePointer<UInt8>,
                                from start: Int,
                                to end: Int,
                                name: [UInt8]) -> Bool {
        guard end - start == name.count else { return false }
        for i in 0..<name.count {
            var c = buffer[start + i]
            if c >= asciiUpperA && c <= asciiUpperZ { c += 0x20 }
            if c != name[i] { return false }
        }
        return true
    }

    /// Parses optional whitespace, one or more ASCII digits, optional whitespace. Anything else
    /// (signs, letters, empty values, absurd lengths) is rejected.
    private static func parseDecimal(_ buffer: UnsafePointer<UInt8>,
                                     from start: Int,
                                     to end: Int) -> Int? {
        var s = start
        var e = end
        while s < e && (buffer[s] == asciiSpace || buffer[s] == asciiTab) { s += 1 }
        while e > s && (buffer[e - 1] == asciiSpace || buffer[e - 1] == asciiTab) { e -= 1 }
        guard s < e, e - s <= 18 else { return nil }

        var value = 0
        for i in s..<e {
            let c = buffer[i]
            guard c >= asciiZero && c <= asciiNine else { return nil }
            value = value * 10 + Int(c - asciiZero)
        }
        return value
    }
}
