import Flynn
import Foundation
import Hitch

// swiftlint:disable identifier_name

public enum HttpMethod {
    case UNKNOWN
    case GET
    case HEAD
    case PUT
    case POST
    case DELETE
}

public enum HttpStatus: Int {

    // MARK: - 1xx Informational
    case `continue` = 100
    case switchingProtocols = 101
    case processing = 102
    case earlyHints = 103

    // MARK: - 2xx Success
    case ok = 200
    case created = 201
    case accepted = 202
    case nonAuthoritativeInformation = 203
    case noContent = 204
    case resetContent = 205
    case partialContent = 206
    case multiStatus = 207
    case alreadyReported = 208
    case imUsed = 226

    // MARK: - 3xx Redirection
    case multipleChoices = 300
    case movedPermanently = 301
    case found = 302
    case seeOther = 303
    case notModified = 304
    case useProxy = 305
    case temporaryRedirect = 307
    case permanentRedirect = 308

    // MARK: - 4xx Client Error
    case badRequest = 400
    case unauthorized = 401
    case paymentRequired = 402
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case notAcceptable = 406
    case proxyAuthenticationRequired = 407
    case requestTimeout = 408
    case conflict = 409
    case gone = 410
    case lengthRequired = 411
    case preconditionFailed = 412
    case requestTooLarge = 413
    case uriTooLong = 414
    case unsupportedMediaType = 415
    case rangeNotSatisfiable = 416
    case expectationFailed = 417
    case imATeapot = 418
    case misdirectedRequest = 421
    case unprocessableContent = 422
    case locked = 423
    case failedDependency = 424
    case tooEarly = 425
    case upgradeRequired = 426
    case preconditionRequired = 428
    case tooManyRequests = 429
    case requestHeaderFieldsTooLarge = 431
    case unavailableForLegalReasons = 451

    // MARK: - 5xx Server Error
    case internalServerError = 500
    case notImplemented = 501
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504
    case httpVersionNotSupported = 505
    case variantAlsoNegotiates = 506
    case insufficientStorage = 507
    case loopDetected = 508
    case notExtended = 510
    case networkAuthenticationRequired = 511

    public var hitch: HalfHitch {
        switch self {
        case .continue: return "HTTP/1.1 100 Continue"
        case .switchingProtocols: return "HTTP/1.1 101 Switching Protocols"
        case .processing: return "HTTP/1.1 102 Processing"
        case .earlyHints: return "HTTP/1.1 103 Early Hints"

        case .ok: return "HTTP/1.1 200 OK"
        case .created: return "HTTP/1.1 201 Created"
        case .accepted: return "HTTP/1.1 202 Accepted"
        case .nonAuthoritativeInformation: return "HTTP/1.1 203 Non-Authoritative Information"
        case .noContent: return "HTTP/1.1 204 No Content"
        case .resetContent: return "HTTP/1.1 205 Reset Content"
        case .partialContent: return "HTTP/1.1 206 Partial Content"
        case .multiStatus: return "HTTP/1.1 207 Multi-Status"
        case .alreadyReported: return "HTTP/1.1 208 Already Reported"
        case .imUsed: return "HTTP/1.1 226 IM Used"

        case .multipleChoices: return "HTTP/1.1 300 Multiple Choices"
        case .movedPermanently: return "HTTP/1.1 301 Moved Permanently"
        case .found: return "HTTP/1.1 302 Found"
        case .seeOther: return "HTTP/1.1 303 See Other"
        case .notModified: return "HTTP/1.1 304 Not Modified"
        case .useProxy: return "HTTP/1.1 305 Use Proxy"
        case .temporaryRedirect: return "HTTP/1.1 307 Temporary Redirect"
        case .permanentRedirect: return "HTTP/1.1 308 Permanent Redirect"

        case .badRequest: return "HTTP/1.1 400 Bad Request"
        case .unauthorized: return "HTTP/1.1 401 Unauthorized"
        case .paymentRequired: return "HTTP/1.1 402 Payment Required"
        case .forbidden: return "HTTP/1.1 403 Forbidden"
        case .notFound: return "HTTP/1.1 404 Not Found"
        case .methodNotAllowed: return "HTTP/1.1 405 Method Not Allowed"
        case .notAcceptable: return "HTTP/1.1 406 Not Acceptable"
        case .proxyAuthenticationRequired: return "HTTP/1.1 407 Proxy Authentication Required"
        case .requestTimeout: return "HTTP/1.1 408 Request Timeout"
        case .conflict: return "HTTP/1.1 409 Conflict"
        case .gone: return "HTTP/1.1 410 Gone"
        case .lengthRequired: return "HTTP/1.1 411 Length Required"
        case .preconditionFailed: return "HTTP/1.1 412 Precondition Failed"
        case .requestTooLarge: return "HTTP/1.1 413 Request Too Large"
        case .uriTooLong: return "HTTP/1.1 414 URI Too Long"
        case .unsupportedMediaType: return "HTTP/1.1 415 Unsupported Media Type"
        case .rangeNotSatisfiable: return "HTTP/1.1 416 Range Not Satisfiable"
        case .expectationFailed: return "HTTP/1.1 417 Expectation Failed"
        case .imATeapot: return "HTTP/1.1 418 I'm a teapot"
        case .misdirectedRequest: return "HTTP/1.1 421 Misdirected Request"
        case .unprocessableContent: return "HTTP/1.1 422 Unprocessable Content"
        case .locked: return "HTTP/1.1 423 Locked"
        case .failedDependency: return "HTTP/1.1 424 Failed Dependency"
        case .tooEarly: return "HTTP/1.1 425 Too Early"
        case .upgradeRequired: return "HTTP/1.1 426 Upgrade Required"
        case .preconditionRequired: return "HTTP/1.1 428 Precondition Required"
        case .tooManyRequests: return "HTTP/1.1 429 Too Many Requests"
        case .requestHeaderFieldsTooLarge: return "HTTP/1.1 431 Request Header Fields Too Large"
        case .unavailableForLegalReasons: return "HTTP/1.1 451 Unavailable For Legal Reasons"

        case .notImplemented: return "HTTP/1.1 501 Not Implemented"
        case .badGateway: return "HTTP/1.1 502 Bad Gateway"
        case .serviceUnavailable: return "HTTP/1.1 503 Service Unavailable"
        case .gatewayTimeout: return "HTTP/1.1 504 Gateway Timeout"
        case .httpVersionNotSupported: return "HTTP/1.1 505 HTTP Version Not Supported"
        case .variantAlsoNegotiates: return "HTTP/1.1 506 Variant Also Negotiates"
        case .insufficientStorage: return "HTTP/1.1 507 Insufficient Storage"
        case .loopDetected: return "HTTP/1.1 508 Loop Detected"
        case .notExtended: return "HTTP/1.1 510 Not Extended"
        case .networkAuthenticationRequired: return "HTTP/1.1 511 Network Authentication Required"

        default: return "HTTP/1.1 500 Internal Server Error"
        }
    }
}

public enum HttpEncoding: HalfHitch {
    case identity = "identity"
    case gzip = "gzip"
    case compress = "compress"
    case deflate = "deflate"
    case br = "br"
}

public enum HttpContentType: HalfHitch {
    case none = "none"
    case any = "any"
    case arc = "arc"
    case avi = "avi"
    case azw = "azw"
    case bin = "bin"
    case bmp = "bmp"
    case bz = "bz"
    case bz2 = "bz2"
    case csh = "csh"
    case css = "css"
    case csv = "csv"
    case doc = "doc"
    case docx = "docx"
    case eot = "eot"
    case epub = "epub"
    case formData = "form-data"
    case gz = "gz"
    case gif = "gif"
    case htm = "htm"
    case html = "html"
    case ico = "ico"
    case ics = "ics"
    case jar = "jar"
    case jpeg = "jpeg"
    case jpg = "jpg"
    case js = "js"
    case json = "json"
    case jsonld = "jsonld"
    case mid = "mid"
    case midi = "midi"
    case mixed = "mixed"
    case mjs = "mjs"
    case mp3 = "mp3"
    case mpeg = "mpeg"
    case mpkg = "mpkg"
    case odp = "odp"
    case ods = "ods"
    case odt = "odt"
    case oga = "oga"
    case ogv = "ogv"
    case ogx = "ogx"
    case opus = "opus"
    case otf = "otf"
    case png = "png"
    case pdf = "pdf"
    case php = "php"
    case ppt = "ppt"
    case pptx = "pptx"
    case rar = "rar"
    case rtf = "rtf"
    case sh = "sh"
    case svg = "svg"
    case swf = "swf"
    case tar = "tar"
    case tif = "tif"
    case tiff = "tiff"
    case ts = "ts"
    case ttf = "ttf"
    case txt = "txt"
    case vsd = "vsd"
    case wav = "wav"
    case weba = "weba"
    case webm = "webm"
    case webp = "webp"
    case woff = "woff"
    case woff2 = "woff2"
    case xhtml = "xhtml"
    case xls = "xls"
    case xlsx = "xlsx"
    case xml = "xml"
    case rss = "rss"
    case xul = "xul"
    case zip = "zip"
    case _3gp = "3gp"
    case _3g2 = "3g2"
    case _7z = "7z"
    case force = "force"

    public static func fromPath(_ path: Hitchable) -> HttpContentType {
        if let lastDot = path.lastIndex(of: .dot),
           let fileExt = path.substring(lastDot + 1, path.count) {
            if let type = HttpContentType(rawValue: fileExt.halfhitch()) {
                return type
            }
        }
        return .txt
    }

    public var hitch: HalfHitch {
        switch self {
        case .none: return ""
        case .any: return "*/*"
        case .arc: return "application/x-freearc"
        case .avi: return "video/x-msvideo"
        case .azw: return "application/vnd.amazon.ebook"
        case .bin: return "application/octet-stream"
        case .bmp: return "image/bmp"
        case .bz: return "application/x-bzip"
        case .bz2: return "application/x-bzip2"
        case .csh: return "application/x-csh"
        case .css: return "text/css"
        case .csv: return "text/csv"
        case .doc: return "application/msword"
        case .docx: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .eot: return "application/vnd.ms-fontobject"
        case .epub: return "application/epub+zip"
        case .formData: return "multipart/form-data"
        case .gz: return "application/gzip"
        case .gif: return "image/gif"
        case .htm: return "text/html"
        case .html: return "text/html"
        case .ico: return "image/vnd.microsoft.icon"
        case .ics: return "text/calendar"
        case .jar: return "application/java-archive"
        case .jpeg: return "image/jpeg"
        case .jpg: return "image/jpeg"
        case .js: return "text/javascript"
        case .json: return "application/json"
        case .jsonld: return "application/ld+json"
        case .mid: return "audio/midi"
        case .midi: return "audio/midi"
        case .mixed: return "multipart/mixed"
        case .mjs: return "text/javascript"
        case .mp3: return "audio/mpeg"
        case .mpeg: return "video/mpeg"
        case .mpkg: return "application/vnd.apple.installer+xml"
        case .odp: return "application/vnd.oasis.opendocument.presentation"
        case .ods: return "application/vnd.oasis.opendocument.spreadsheet"
        case .odt: return "application/vnd.oasis.opendocument.text"
        case .oga: return "audio/ogg"
        case .ogv: return "video/ogg"
        case .ogx: return "application/ogg"
        case .opus: return "audio/opus"
        case .otf: return "font/otf"
        case .png: return "image/png"
        case .pdf: return "application/pdf"
        case .php: return "application/php"
        case .ppt: return "application/vnd.ms-powerpoint"
        case .pptx: return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case .rar: return "application/x-rar-compressed"
        case .rtf: return "application/rtf"
        case .sh: return "application/x-sh"
        case .svg: return "image/svg+xml"
        case .swf: return "application/x-shockwave-flash"
        case .tar: return "application/x-tar"
        case .tif: return "image/tiff"
        case .tiff: return "image/tiff"
        case .ts: return "video/mp2t"
        case .ttf: return "font/ttf"
        case .txt: return "text/plain"
        case .vsd: return "application/vnd.visio"
        case .wav: return "audio/wav"
        case .weba: return "audio/webm"
        case .webm: return "video/webm"
        case .webp: return "image/webp"
        case .woff: return "font/woff"
        case .woff2: return "font/woff2"
        case .xhtml: return "application/xhtml+xml"
        case .xls: return "application/vnd.ms-excel"
        case .xlsx: return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .xml: return "application/xml"
        case .rss: return "application/rss+xml"
        case .xul: return "application/vnd.mozilla.xul+xml"
        case .zip: return "application/zip"
        case ._3gp: return "video/3gpp"
        case ._3g2: return "video/3gpp2"
        case ._7z: return "application/x-7z-compressed"
        case .force: return "application/force-download"
        }
    }
}












































































