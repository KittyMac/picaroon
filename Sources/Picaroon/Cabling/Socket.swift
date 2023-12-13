import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Glibc)
private let posix_gethostbyname = Glibc.gethostbyname
private let posix_inet_ntop = Glibc.inet_ntop
private let posix_shutdown = Glibc.shutdown
private let posix_close = Glibc.close
private let posix_send = Glibc.send
private let posix_recv = Glibc.recv
private let posix_listen = Glibc.listen
private let posix_accept = Glibc.accept
private let posix_getpeername = Glibc.getpeername
private let posix_poll = Glibc.poll
#endif
#if canImport(Darwin)
private let posix_gethostbyname = Darwin.gethostbyname
private let posix_inet_ntop = Darwin.inet_ntop
private let posix_shutdown = Darwin.shutdown
private let posix_close = Darwin.close
private let posix_send = Darwin.send
private let posix_recv = Darwin.recv
private let posix_listen = Darwin.listen
private let posix_accept = Darwin.accept
private let posix_getpeername = Darwin.getpeername
private let posix_poll = Darwin.poll
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
        _ = posix_shutdown(socketFd, Int32(SHUT_RDWR))
        _ = posix_close(socketFd)
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
        guard let bytes = bytes else { return -1 }
        guard socketFd >= 0 else { return -1 }
        var cptr = bytes
        let startPtr = bytes
        let endPtr = startPtr + count
        
        while cptr < endPtr {
            let bytesWritten = posix_send(socketFd, cptr, endPtr - cptr, Int32(MSG_NOSIGNAL))
            
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
    public func poll() -> Int {
        guard socketFd >= 0 else { return -1 }
        
        let nfds: nfds_t = 1
        let timeout: Int32 = 0
        var fds: pollfd = pollfd(fd: socketFd,
                                 events: Int16(POLLIN),
                                 revents: 0)
        return Int(posix_poll(&fds, nfds, timeout))
    }
    
    @discardableResult
    public func recv(bytes: UnsafeMutablePointer<UInt8>?,
                     count: Int) -> Int {
        guard let bytes = bytes else { return -1 }
        guard socketFd >= 0 else { return -1 }
        let cptr = bytes
        let startPtr = bytes
        let endPtr = startPtr + count
                            
        let bytesRead = posix_recv(socketFd, cptr, endPtr - cptr, Int32(MSG_NOSIGNAL))
        
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
        let sockAddrInSize = socklen_t(MemoryLayout<sockaddr_in>.size)
                                       
        sockAddressIn.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, address, &(sockAddressIn.sin_addr))
        sockAddressIn.sin_port = UInt16(clamping: port).bigEndian
        
        let result = withUnsafePointer(to: &sockAddressIn) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return bind(socketFd, $0, sockAddrInSize)
            }
        }
                
        if result < 0 {
            return -1
        }
        
        let ret = posix_listen(socketFd, 128)
        if ret < 0 {
            self.close()
            return -1
        }
        
        return 0
    }
    
    @discardableResult
    public func accept(blocking: Bool = true, clientAddress: inout String) -> Socket? {
        clientAddress = ""
        
        var clientAddr = sockaddr_in()
        var sockAddrInSize = socklen_t(MemoryLayout<sockaddr_in>.size)

        let clientFd: Int32 = withUnsafeMutablePointer(to: &clientAddr) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return posix_accept(socketFd, $0, &sockAddrInSize)
            }
        }
        
        let socket = Socket(socketFd: clientFd,
                            blocking: blocking)
        
        let capacity = Int(INET6_ADDRSTRLEN)
        guard let scratch_ptr = malloc(capacity)?.bindMemory(to: CChar.self, capacity: capacity) else { return socket }
        
        _ = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                posix_getpeername(clientFd, $0, &sockAddrInSize)
            }
        }

        if inet_ntop(Int32(clientAddr.sin_family), &clientAddr.sin_addr, scratch_ptr, socklen_t(INET6_ADDRSTRLEN)) != nil {
            let count = strnlen(scratch_ptr, Int(INET6_ADDRSTRLEN))
            scratch_ptr.withMemoryRebound(to: UInt8.self, capacity: count) { hitchPtr in
                clientAddress = Hitch(bytes: hitchPtr, offset: 0, count: count).toString()
            }
        }
                
        return socket
    }
    
    @discardableResult
    public func clientAddress() -> String {
        var clientAddress = ""
        
        var clientAddr = sockaddr_in()
        var sockAddrInSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let capacity = Int(INET6_ADDRSTRLEN)
        guard let scratch_ptr = malloc(capacity)?.bindMemory(to: CChar.self, capacity: capacity) else { return clientAddress }
        
        _ = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                posix_getpeername(socketFd, $0, &sockAddrInSize)
            }
        }

        if inet_ntop(Int32(clientAddr.sin_family), &clientAddr.sin_addr, scratch_ptr, socklen_t(INET6_ADDRSTRLEN)) != nil {
            let count = strnlen(scratch_ptr, Int(INET6_ADDRSTRLEN))
            scratch_ptr.withMemoryRebound(to: UInt8.self, capacity: count) { hitchPtr in
                clientAddress = Hitch(bytes: hitchPtr, offset: 0, count: count).toString()
            }
        }
        
        free(scratch_ptr)
                
        return clientAddress
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
