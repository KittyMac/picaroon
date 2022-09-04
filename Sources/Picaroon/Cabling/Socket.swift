import Foundation
import Flynn
import Hitch

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
        
        applyOptions(blocking: blocking)
    }
        
    public init?(blocking: Bool = true) {
        #if os(Android)
        if blocking {
            socketFd = socket(AF_INET, SOCK_STREAM, 0)
        } else {
            socketFd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0)
        }
        #elseif os(Linux)
        if blocking {
            socketFd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        } else {
            socketFd = socket(AF_INET, Int32(SOCK_STREAM.rawValue | SOCK_NONBLOCK.rawValue), 0)
        }
        #else
        socketFd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        
        guard socketFd >= 0 else { return nil }
        
        applyOptions(blocking: blocking)
    }
    
    deinit {
        self.close()
    }
    
    private func applyOptions(blocking: Bool) {
        #if os(Linux) || os(Android)
        #else
        var one: Int32 = 1
        setsockopt(socketFd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<timeval>.stride))
        
        let flags = fcntl(socketFd, F_GETFL)
        if blocking {
            _ = fcntl(socketFd, F_SETFL, flags & ~O_NONBLOCK)
        } else {
            _ = fcntl(socketFd, F_SETFL, flags | O_NONBLOCK)
        }
        #endif
    }
    
    public func setReadTimeout(milliseconds value: UInt = 0) {
        var timeout = timeval()
        if value > 0 {
            timeout.tv_sec = Int(Double(value / 1000))
            let uSecs = Int32(Double(value % 1000)) * 1000
            #if os(Linux) || os(Android)
            timeout.tv_usec = Int(uSecs)
            #else
            timeout.tv_usec = Int32(uSecs)
            #endif
        }
        #if os(Android)
        setsockopt (socketFd, SOL_SOCKET, SO_RCVTIMEO_NEW, &timeout, socklen_t(MemoryLayout<timeval>.stride))
        #else
        setsockopt (socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.stride))
        #endif
    }
    
    public func setWriteTimeout(milliseconds: UInt = 0) {
        var timeout = timeval()
        if milliseconds > 0 {
            timeout.tv_sec = Int(milliseconds / 1000)
            let uSecs = (milliseconds % 1000) * 1000
            #if os(Linux) || os(Android)
            timeout.tv_usec = Int(uSecs)
            #else
            timeout.tv_usec = Int32(uSecs)
            #endif
        }
        #if os(Android)
        setsockopt (socketFd, SOL_SOCKET, SO_SNDTIMEO_NEW, &timeout, socklen_t(MemoryLayout<timeval>.stride))
        #else
        setsockopt (socketFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.stride))
        #endif
    }
    
    public func close() {
        guard socketFd >= 0 else { return }
        #if os(Linux) || os(Android)
        Glibc.shutdown(socketFd, Int32(SHUT_RDWR))
        Glibc.close(socketFd)
        #else
        Darwin.shutdown(socketFd, Int32(SHUT_RDWR))
        Darwin.close(socketFd)
        #endif
        socketFd = -1
    }
    
    @inlinable @inline(__always)
    public func isClosed() -> Bool {
        return socketFd < 0
    }
    
    @inlinable @inline(__always)
    public func fd() -> Int32 {
        return socketFd
    }
    
    @discardableResult
    @inlinable @inline(__always)
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
        guard let bytes = bytes else { return -1 }
        guard socketFd >= 0 else { return -1 }
        var cptr = bytes
        let startPtr = bytes
        let endPtr = startPtr + count
        
        while cptr < endPtr {
            #if os(Linux) || os(Android)
            let bytesWritten = Glibc.send(socketFd, cptr, endPtr - cptr, Int32(MSG_NOSIGNAL))
            #else
            let bytesWritten = Darwin.send(socketFd, cptr, endPtr - cptr, Int32(MSG_NOSIGNAL))
            #endif
            
            if (bytesWritten < 0) {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return cptr - startPtr
                }
                self.close()
                return -1
            } else if (bytesWritten == 0) {
                self.close()
                return 0
            }
            cptr += bytesWritten
        }
        return cptr - startPtr
    }
    
    @discardableResult
    public func recv(bytes: UnsafeMutablePointer<UInt8>?,
                     count: Int) -> Int {
        guard let bytes = bytes else { return -1 }
        guard socketFd >= 0 else { return -1 }
        let cptr = bytes
        let startPtr = bytes
        let endPtr = startPtr + count
                            
        #if os(Linux) || os(Android)
        let bytesRead = Glibc.recv(socketFd, cptr, endPtr - cptr, Int32(MSG_NOSIGNAL))
        #else
        let bytesRead = Darwin.recv(socketFd, cptr, endPtr - cptr, Int32(MSG_NOSIGNAL))
        #endif
        
        if (bytesRead <= 0) {
            if bytesRead < 0 && errno == EWOULDBLOCK || errno == EAGAIN {
                return 0
            }
            self.close()
            return -1
        }
        return bytesRead
    }
    
    @discardableResult
    public func listen(address: String,
                       port: Int) -> Int {
        guard socketFd >= 0 else { return -1 }
        
        var one: Int32 = 1
        setsockopt(socketFd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<timeval>.stride))
        
        var sockAddressIn = sockaddr_in()
        sockAddressIn.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, address, &(sockAddressIn.sin_addr))
        sockAddressIn.sin_port = UInt16(clamping: port).bigEndian
        
        let result = withUnsafePointer(to: &sockAddressIn) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return bind(socketFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
                
        if result < 0 {
            return -1
        }
        
        #if os(Linux) || os(Android)
        let ret = Glibc.listen(socketFd, 128)
        #else
        let ret = Darwin.listen(socketFd, 128)
        #endif
        
        if ret < 0 {
            self.close()
            return -1
        }
        
        return 0
    }
    
    @discardableResult
    public func accept(blocking: Bool = true) -> Socket? {
        
        #if os(Linux) || os(Android)
        let clientFd = Glibc.accept(socketFd, nil, nil)
        #else
        let clientFd = Darwin.accept(socketFd, nil, nil)
        #endif
        
        let socket = Socket(socketFd: clientFd,
                            blocking: blocking)
        
        
        return socket
    }
    
    @discardableResult
    public func connectTo(address: String,
                          port: Int) -> Int {
        guard socketFd >= 0 else { return -1 }
        
        var sockAddressIn = sockaddr_in()
        sockAddressIn.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, address, &(sockAddressIn.sin_addr))
        sockAddressIn.sin_port = UInt16(clamping: port).bigEndian
        
        //var timeout = timeval()
        //timeout.tv_sec = 5
        //timeout.tv_usec = 0
        //setsockopt (socketFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        //setsockopt (socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                
        let _ = withUnsafePointer(to: &sockAddressIn) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return connect(socketFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return 0
    }
}
