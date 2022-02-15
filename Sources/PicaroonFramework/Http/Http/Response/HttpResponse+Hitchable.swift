import Flynn
import Foundation
import Hitch

public protocol ConvertableToPayloadable {
    var payload: Payloadable { get }
}

public protocol Payloadable {
    var count: Int { get }
    func using(_ block: (UnsafePointer<UInt8>?, Int) -> ())
}

extension HalfHitch: ConvertableToPayloadable {
    public var payload: Payloadable { self }
}

extension Hitch: ConvertableToPayloadable {
    public var payload: Payloadable { self }
}

extension Data: ConvertableToPayloadable {
    public var payload: Payloadable { self }
}

extension Hitch: Payloadable {
    
}

extension HalfHitch: Payloadable {
    
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

