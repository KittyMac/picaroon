import Flynn
import Foundation
import Hitch

public protocol Payloadable {
    func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T?
}

extension HalfHitch: Payloadable {
    
}

extension Hitch: Payloadable {
    
}

extension Data: Payloadable {
    public func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T? {
        return withUnsafeBytes { unsafeRawBufferPointer in
            let unsafeBufferPointer = unsafeRawBufferPointer.bindMemory(to: UInt8.self)
            guard let bytes = unsafeBufferPointer.baseAddress else { return nil }
            return block(bytes, count)
        }
    }
}

extension StaticString: Payloadable {
    public func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T? {
        return block(utf8Start, utf8CodeUnitCount)
    }
}

extension String: Payloadable {
    public func using<T>(_ block: (UnsafePointer<UInt8>?, Int) -> T?) -> T? {
        return withCString { bytes in
            var ptr = bytes
            while ptr.pointee != 0 {
                ptr += 1
            }
            let count = ptr - bytes
            
            return bytes.withMemoryRebound(to: UInt8.self, capacity: count) { ptr in
                return block(ptr, count)
            }
        }
    }
}

