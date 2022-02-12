import Flynn
import Foundation
import Hitch

public typealias PayloadableUsing = (UnsafePointer<UInt8>?, Int) -> ()

public protocol Payloadable {
    var count: Int { get }
    
    func using(_ block: PayloadableUsing)
}

extension Data: Payloadable {
    public func using(_ block: PayloadableUsing) {
        withUnsafeBytes { unsafeRawBufferPointer in
            let unsafeBufferPointer = unsafeRawBufferPointer.bindMemory(to: UInt8.self)
            guard let bytes = unsafeBufferPointer.baseAddress else { return }
            block(bytes, count)
        }
    }
}

extension Hitch: Payloadable {
    public func using(_ block: PayloadableUsing) {
        block(raw(), count)
    }
}
