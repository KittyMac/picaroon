import Flynn
import Foundation
import Hitch
import SWCompression

extension Data {
    public var isGzipped: Bool {
        return self.starts(with: [0x1f, 0x8b])  // check magic number
    }
}

struct GzipError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    public var localizedDescription: String {
        return message
    }
}

public protocol Payloadable {
    func gzipped() throws -> Data
    func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T?
}

extension HalfHitch: Payloadable {
    public func gzipped() throws -> Data {
        return try GzipArchive.archive(data: dataNoCopy())
    }
}

extension Hitch: Payloadable {
    public func gzipped() throws -> Data {
        return try GzipArchive.archive(data: dataNoCopy())
    }
}

extension Data: Payloadable {
    public func gzipped() throws -> Data {
        guard isGzipped == false else { return self }
        return try GzipArchive.archive(data: self)
    }
    
    public func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T? {
        return withUnsafeBytes { unsafeRawBufferPointer in
            let unsafeBufferPointer = unsafeRawBufferPointer.bindMemory(to: UInt8.self)
            guard let bytes = unsafeBufferPointer.baseAddress else { return nil }
            return block(bytes, count)
        }
    }
}

extension StaticString: Payloadable {
    public func gzipped() throws -> Data {
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: self.utf8Start),
                        count: self.utf8CodeUnitCount,
                        deallocator: .none)
        return try GzipArchive.archive(data: data)
    }
    
    public func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T? {
        return block(utf8Start, utf8CodeUnitCount)
    }
}

extension String: Payloadable {
    public func gzipped() throws -> Data {
        guard let data = data(using: .utf8) else { throw GzipError("failed to convert string to data") }
        return try GzipArchive.archive(data: data)
    }
    
    public func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T? {
        return withCString { bytes in
            var ptr = bytes
            while ptr[0] != 0 {
                ptr += 1
            }
            let count = ptr - bytes
            
            return bytes.withMemoryRebound(to: UInt8.self, capacity: count) { ptr in
                return block(ptr, count)
            }
        }
    }
}

