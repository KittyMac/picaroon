import Flynn
import Foundation
import Hitch

// swiftlint:disable identifier_name

private let hitchHttpOk = "HTTP/1.1 200 OK".hitch()
private let hitchHttpNotModified = "HTTP/1.1 304 Not Modified".hitch()
private let hitchHttpBadRequest = "HTTP/1.1 400 Bad Request".hitch()
private let hitchHttpNotFound = "HTTP/1.1 404 Not Found".hitch()
private let hitchHttpRequestTimeout = "HTTP/1.1 408 Request Timeout".hitch()
private let hitchHttpRequestTooLarge = "HTTP/1.1 413 Request Too Large".hitch()
private let hitchHttpServiceUnavailable = "HTTP/1.1 503 Service Unavailable".hitch()
private let hitchHttpInternalServerError = "HTTP/1.1 500 Internal Server Error".hitch()

public enum HttpMethod {
    case UNKNOWN
    case GET
    case HEAD
    case PUT
    case POST
    case DELETE
}

public enum HttpStatus: Int {
    case ok = 200
    case notModified = 304
    case badRequest = 400
    case notFound = 404
    case requestTimeout = 408
    case requestTooLarge = 413
    case internalServerError = 500
    case serviceUnavailable = 503

    public var hitch: Hitch {
        switch self {
        case .ok: return hitchHttpOk
        case .notModified: return hitchHttpNotModified
        case .badRequest: return hitchHttpBadRequest
        case .notFound: return hitchHttpNotFound
        case .requestTimeout: return hitchHttpRequestTimeout
        case .requestTooLarge: return hitchHttpRequestTooLarge
        case .serviceUnavailable: return hitchHttpServiceUnavailable
        default: return hitchHttpInternalServerError
        }
    }
}

public enum HttpEncoding: Hitch {
    case identity = "identity"
    case gzip = "gzip"
    case compress = "compress"
    case deflate = "deflate"
    case br = "br"
}

public enum HttpContentType: Hitch {
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
    case xul = "xul"
    case zip = "zip"
    case _3gp = "3gp"
    case _3g2 = "3g2"
    case _7z = "7z"
    case force = "force"

    public static func fromPath(_ path: Hitchable) -> HttpContentType {
        if let lastDot = path.lastIndex(of: .dot),
           let fileExt = path.substring(lastDot + 1, path.count) {
            if let type = HttpContentType(rawValue: fileExt) {
                return type
            }
        }
        return .txt
    }

    public var hitch: Hitch {
        switch self {
        case .arc: return hitchMimeTypeArc
        case .avi: return hitchMimeTypeAvi
        case .azw: return hitchMimeTypeAzw
        case .bin: return hitchMimeTypeBin
        case .bmp: return hitchMimeTypeBmp
        case .bz: return hitchMimeTypeBz
        case .bz2: return hitchMimeTypeBz2
        case .csh: return hitchMimeTypeCsh
        case .css: return hitchMimeTypeCss
        case .csv: return hitchMimeTypeCsv
        case .doc: return hitchMimeTypeDoc
        case .docx: return hitchMimeTypeDocx
        case .eot: return hitchMimeTypeEot
        case .epub: return hitchMimeTypeEpub
        case .formData: return hitchMimeTypeFormData
        case .gz: return hitchMimeTypeGz
        case .gif: return hitchMimeTypeGif
        case .htm: return hitchMimeTypeHtm
        case .html: return hitchMimeTypeHtml
        case .ico: return hitchMimeTypeIco
        case .ics: return hitchMimeTypeIcs
        case .jar: return hitchMimeTypeJar
        case .jpeg: return hitchMimeTypeJpeg
        case .jpg: return hitchMimeTypeJpg
        case .js: return hitchMimeTypeJs
        case .json: return hitchMimeTypeJson
        case .jsonld: return hitchMimeTypeJsonld
        case .mid: return hitchMimeTypeMid
        case .midi: return hitchMimeTypeMidi
        case .mjs: return hitchMimeTypeMjs
        case .mp3: return hitchMimeTypeMp3
        case .mpeg: return hitchMimeTypeMpeg
        case .mpkg: return hitchMimeTypeMpkg
        case .odp: return hitchMimeTypeOdp
        case .ods: return hitchMimeTypeOds
        case .odt: return hitchMimeTypeOdt
        case .oga: return hitchMimeTypeOga
        case .ogv: return hitchMimeTypeOgv
        case .ogx: return hitchMimeTypeOgx
        case .opus: return hitchMimeTypeOpus
        case .otf: return hitchMimeTypeOtf
        case .png: return hitchMimeTypePng
        case .pdf: return hitchMimeTypePdf
        case .php: return hitchMimeTypePhp
        case .ppt: return hitchMimeTypePpt
        case .pptx: return hitchMimeTypePptx
        case .rar: return hitchMimeTypeRar
        case .rtf: return hitchMimeTypeRtf
        case .sh: return hitchMimeTypeSh
        case .svg: return hitchMimeTypeSvg
        case .swf: return hitchMimeTypeSwf
        case .tar: return hitchMimeTypeTar
        case .tif: return hitchMimeTypeTif
        case .tiff: return hitchMimeTypeTiff
        case .ts: return hitchMimeTypeTs
        case .ttf: return hitchMimeTypeTtf
        case .txt: return hitchMimeTypeTxt
        case .vsd: return hitchMimeTypeVsd
        case .wav: return hitchMimeTypeWav
        case .weba: return hitchMimeTypeWeba
        case .webm: return hitchMimeTypeWebm
        case .webp: return hitchMimeTypeWebp
        case .woff: return hitchMimeTypeWoff
        case .woff2: return hitchMimeTypeWoff2
        case .xhtml: return hitchMimeTypeXhtml
        case .xls: return hitchMimeTypeXls
        case .xlsx: return hitchMimeTypeXlsx
        case .xml: return hitchMimeTypeXml
        case .xul: return hitchMimeTypeXul
        case .zip: return hitchMimeTypeZip
        case ._3gp: return hitchMimeType_3gp
        case ._3g2: return hitchMimeType_3g2
        case ._7z: return hitchMimeType_7z
        case .force: return hitchMimeTypeForce
        }
    }
}

private let hitchMimeTypeArc = "application/x-freearc".hitch()
private let hitchMimeTypeAvi = "video/x-msvideo".hitch()
private let hitchMimeTypeAzw = "application/vnd.amazon.ebook".hitch()
private let hitchMimeTypeBin = "application/octet-stream".hitch()
private let hitchMimeTypeBmp = "image/bmp".hitch()
private let hitchMimeTypeBz =  "application/x-bzip".hitch()
private let hitchMimeTypeBz2 = "application/x-bzip2".hitch()
private let hitchMimeTypeCsh = "application/x-csh".hitch()
private let hitchMimeTypeCss = "text/css".hitch()
private let hitchMimeTypeCsv = "text/csv".hitch()
private let hitchMimeTypeDoc = "application/msword".hitch()
private let hitchMimeTypeDocx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".hitch()
private let hitchMimeTypeEot = "application/vnd.ms-fontobject".hitch()
private let hitchMimeTypeEpub = "application/epub+zip".hitch()
private let hitchMimeTypeFormData = "multipart/form-data".hitch()
private let hitchMimeTypeGz =  "application/gzip".hitch()
private let hitchMimeTypeGif = "image/gif".hitch()
private let hitchMimeTypeHtm = "text/html".hitch()
private let hitchMimeTypeHtml = "text/html".hitch()
private let hitchMimeTypeIco = "image/vnd.microsoft.icon".hitch()
private let hitchMimeTypeIcs = "text/calendar".hitch()
private let hitchMimeTypeJar = "application/java-archive".hitch()
private let hitchMimeTypeJpeg = "image/jpeg".hitch()
private let hitchMimeTypeJpg = "image/jpeg".hitch()
private let hitchMimeTypeJs = "text/javascript".hitch()
private let hitchMimeTypeJson = "application/json".hitch()
private let hitchMimeTypeJsonld = "application/ld+json".hitch()
private let hitchMimeTypeMid = "audio/midi".hitch()
private let hitchMimeTypeMidi = "audio/midi".hitch()
private let hitchMimeTypeMjs = "text/javascript".hitch()
private let hitchMimeTypeMp3 = "audio/mpeg".hitch()
private let hitchMimeTypeMpeg = "video/mpeg".hitch()
private let hitchMimeTypeMpkg = "application/vnd.apple.installer+xml".hitch()
private let hitchMimeTypeOdp = "application/vnd.oasis.opendocument.presentation".hitch()
private let hitchMimeTypeOds = "application/vnd.oasis.opendocument.spreadsheet".hitch()
private let hitchMimeTypeOdt = "application/vnd.oasis.opendocument.text".hitch()
private let hitchMimeTypeOga = "audio/ogg".hitch()
private let hitchMimeTypeOgv = "video/ogg".hitch()
private let hitchMimeTypeOgx = "application/ogg".hitch()
private let hitchMimeTypeOpus = "audio/opus".hitch()
private let hitchMimeTypeOtf = "font/otf".hitch()
private let hitchMimeTypePng = "image/png".hitch()
private let hitchMimeTypePdf = "application/pdf".hitch()
private let hitchMimeTypePhp = "application/php".hitch()
private let hitchMimeTypePpt = "application/vnd.ms-powerpoint".hitch()
private let hitchMimeTypePptx = "application/vnd.openxmlformats-officedocument.presentationml.presentation".hitch()
private let hitchMimeTypeRar = "application/x-rar-compressed".hitch()
private let hitchMimeTypeRtf = "application/rtf".hitch()
private let hitchMimeTypeSh = "application/x-sh".hitch()
private let hitchMimeTypeSvg = "image/svg+xml".hitch()
private let hitchMimeTypeSwf = "application/x-shockwave-flash".hitch()
private let hitchMimeTypeTar = "application/x-tar".hitch()
private let hitchMimeTypeTif = "image/tiff".hitch()
private let hitchMimeTypeTiff = "image/tiff".hitch()
private let hitchMimeTypeTs = "video/mp2t".hitch()
private let hitchMimeTypeTtf = "font/ttf".hitch()
private let hitchMimeTypeTxt = "text/plain".hitch()
private let hitchMimeTypeVsd = "application/vnd.visio".hitch()
private let hitchMimeTypeWav = "audio/wav".hitch()
private let hitchMimeTypeWeba = "audio/webm".hitch()
private let hitchMimeTypeWebm = "video/webm".hitch()
private let hitchMimeTypeWebp = "image/webp".hitch()
private let hitchMimeTypeWoff = "font/woff".hitch()
private let hitchMimeTypeWoff2 = "font/woff2".hitch()
private let hitchMimeTypeXhtml = "application/xhtml+xml".hitch()
private let hitchMimeTypeXls = "application/vnd.ms-excel".hitch()
private let hitchMimeTypeXlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".hitch()
private let hitchMimeTypeXml = "application/xml".hitch()
private let hitchMimeTypeXul = "application/vnd.mozilla.xul+xml".hitch()
private let hitchMimeTypeZip = "application/zip".hitch()
private let hitchMimeType_3gp = "video/3gpp".hitch()
private let hitchMimeType_3g2 = "video/3gpp2".hitch()
private let hitchMimeType_7z = "application/x-7z-compressed".hitch()
private let hitchMimeTypeForce = "application/force-download".hitch()
