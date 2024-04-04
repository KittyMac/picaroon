import Foundation
import Flynn
import Hitch

#if os(Windows)

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class Socket {
    
    @usableFromInline
    var socketFd: Int32
        
    private init?(socketFd: Int32,
                  blocking: Bool = true) {
        self.socketFd = socketFd
        
        guard socketFd >= 0 else { return nil }
        
        self.socketFd = socketFd
    }
        
    public init?(blocking: Bool = true) {
        self.socketFd = 0
    }
    
    deinit {
        self.close()
    }
    
    private func applyOptions(blocking: Bool) {
        
    }
    
    public func setReadTimeout(milliseconds value: UInt = 0) {
        
    }
    
    public func setWriteTimeout(milliseconds: UInt = 0) {
        
    }
    
    public func close() {
        guard socketFd >= 0 else { return }
        socketFd = -1
    }
    
    @inlinable
    public func isClosed() -> Bool {
        return socketFd < 0
    }
    
    @inlinable
    public func fd() -> Int32 {
        return socketFd
    }
    
    @discardableResult
    @inlinable
    public func send(hitch: Hitch) -> Int {
        return send(bytes: hitch.raw(),
                    count: hitch.count)
    }
    
    @discardableResult
    public func send(data: Data) -> Int {
        return data.withUnsafeBytes { bufferPtr in
            let unsafeBufferPointer = bufferPtr.bindMemory(to: UInt8.self)
            guard let bytes = unsafeBufferPointer.baseAddress else { return -1 }
            return send(bytes: bytes,
                        count: data.count)
        }
    }
    
    @discardableResult
    public func send(bytes: UnsafePointer<UInt8>?,
                     count: Int) -> Int {
        return -1
    }
    
    @discardableResult
    public func poll() -> Int {
        guard socketFd >= 0 else { return -1 }
        return -1
    }
    
    @discardableResult
    public func recv(bytes: UnsafeMutablePointer<UInt8>?,
                     count: Int) -> Int {
        guard let bytes = bytes else { return -1 }
        guard socketFd >= 0 else { return -1 }
        return -1
    }
    
    @discardableResult
    public func listen(address: String,
                       port: Int) -> Int {
        guard socketFd >= 0 else { return -1 }
        return -1
    }
    
    @discardableResult
    public func accept(blocking: Bool = true, clientAddress: inout String) -> Socket? {
        return nil
    }
    
    @discardableResult
    public func clientAddress() -> String {
        return ""
    }
    
    @discardableResult
    public func connectTo(address: String,
                          port: Int) -> Int {
        return -1
    }
}

#endif
