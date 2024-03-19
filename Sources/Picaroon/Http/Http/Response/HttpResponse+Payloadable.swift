import Flynn
import Foundation
import Hitch
import Gzip

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
    func gzipped(level: CompressionLevel) throws -> Data
    func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T?
}

extension HalfHitch: Payloadable {
    public func gzipped(level: CompressionLevel) throws -> Data {
        return try dataNoCopy().gzipped(level: level, wBits: Gzip.maxWindowBits + 16)
    }
}

extension Hitch: Payloadable {
    public func gzipped(level: CompressionLevel) throws -> Data {
        return try dataNoCopy().gzipped(level: level, wBits: Gzip.maxWindowBits + 16)
    }
}

extension Data: Payloadable {
    public func gzipped(level: CompressionLevel) throws -> Data {
        guard isGzipped == false else { return self }
        return try gzipped(level: level, wBits: Gzip.maxWindowBits + 16)
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
    public func gzipped(level: CompressionLevel) throws -> Data {
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: self.utf8Start),
                        count: self.utf8CodeUnitCount,
                        deallocator: .none)
        return try data.gzipped(level: level, wBits: Gzip.maxWindowBits + 16)
    }
    
    public func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T? {
        return block(utf8Start, utf8CodeUnitCount)
    }
}

extension String: Payloadable {
    public func gzipped(level: CompressionLevel) throws -> Data {
        guard let data = data(using: .utf8) else { throw GzipError("failed to convert string to data") }
        return try data.gzipped(level: level, wBits: Gzip.maxWindowBits + 16)
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

