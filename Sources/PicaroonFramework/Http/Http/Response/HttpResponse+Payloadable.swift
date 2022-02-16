import Flynn
import Foundation
import Hitch

public protocol Payloadable {
    func using(_ block: (UnsafePointer<UInt8>?, Int) -> ())
}

extension HalfHitch: Payloadable {
    
}

extension Hitch: Payloadable {
    
}

extension Data: Payloadable {
    public func using(_ block: (UnsafePointer<UInt8>?, Int) -> ()) {
        withUnsafeBytes { unsafeRawBufferPointer in
            let unsafeBufferPointer = unsafeRawBufferPointer.bindMemory(to: UInt8.self)
            guard let bytes = unsafeBufferPointer.baseAddress else { return }
            block(bytes, count)
        }
    }
}

extension StaticString: Payloadable {
    public func using(_ block: (UnsafePointer<UInt8>?, Int) -> ()) {
        block(utf8Start, utf8CodeUnitCount)
    }
}

extension String: Payloadable {
    public func using(_ block: (UnsafePointer<UInt8>?, Int) -> ()) {
        withCString { bytes in
            var ptr = bytes
            while ptr.pointee != 0 {
                ptr += 1
            }
            let count = ptr - bytes
            
            bytes.withMemoryRebound(to: UInt8.self, capacity: count) { ptr in
                block(ptr, count)
            }            
        }
    }
}

