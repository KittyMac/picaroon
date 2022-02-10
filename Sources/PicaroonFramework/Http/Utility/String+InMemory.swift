import Flynn
import Foundation

@propertyWrapper
public struct InMemory: CustomStringConvertible {
    var value: String?
    var bufferPtr: UnsafePointer<UInt8>?
    let startIdx: Int
    let endIdx: Int

    public init(initialValue value: String?,
                _ bufferPtr: UnsafePointer<UInt8>,
                _ startIdx: Int,
                _ endIdx: Int) {
        self.value = value
        self.bufferPtr = bufferPtr
        self.startIdx = startIdx
        self.endIdx = endIdx
    }

    public init() {
        value = nil
        bufferPtr = nil
        startIdx = 0
        endIdx = 0
    }

    @inline(__always)
    func isEmpty() -> Bool {
        return value == nil
    }

    @inline(__always)
    public var wrappedValue: String? {
        get {
            if value == nil && (startIdx >= endIdx) {
                return nil
            }
            if let value = value {
                return value
            }
            if  let bufferPtr = bufferPtr {
                return String(bytesNoCopy: UnsafeMutableRawPointer(mutating: (bufferPtr + startIdx)),
                              length: (bufferPtr + endIdx) - (bufferPtr + startIdx),
                              encoding: .utf8,
                              freeWhenDone: false)
            }
            return nil
        }
        set { value = newValue }
    }

    public var projectedValue: Self {
      get { self }
      set { self = newValue }
    }

    public var description: String {
        if let value = wrappedValue {
            return value
        }
        return ""
    }

}
