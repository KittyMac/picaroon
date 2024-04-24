import Foundation
import Flynn
import Hitch
import WinSDK

#if os(Windows)

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

var wsaData = WSAData()
var wsaInited = false
let wsaLock = NSLock()

private func MAKEWORD(_ a: UInt16, _ b: UInt16) -> UInt16 {
    return (a & 0xff) | (b & 0xff) << 8
}

private func checkWAS() -> Bool {
    wsaLock.lock()
    if wsaInited == false {
        // ((WORD)(((BYTE)(((DWORD_PTR)(a)) & 0xff)) | ((WORD)((BYTE)(((DWORD_PTR)(b)) & 0xff))) << 8))
        if WSAStartup(MAKEWORD(2, 2), &wsaData) != 0 {
            return false
        }
        wsaInited = true
    }
    wsaLock.unlock()
    return true
}

public class Socket {
    let AF_INET: Int32 = 0
    let SOCK_STREAM: Int32 = 1
    let IPPROTO_TCP: Int32 = 6
    
    @usableFromInline
    var socketFd: Int32
        
    private init?(socketFd: Int32,
                  blocking: Bool = true) {
        guard checkWAS() else { return nil }
        
        self.socketFd = socketFd
        
        guard socketFd >= 0 else { return nil }
        
        applyOptions(blocking: blocking)
    }
        
    public init?(blocking: Bool = true) {
        guard checkWAS() else { return nil }
        
        socketFd = Int32(socket(AF_INET, SOCK_STREAM, IPPROTO_TCP))
        if (socketFd == INVALID_SOCKET) {
            return nil
        }
        
        guard socketFd >= 0 else { return nil }
        
        applyOptions(blocking: blocking)
    }
    
    deinit {
        self.close()
    }
    
    private func applyOptions(blocking: Bool) {
        // 1 for non-blocking, 0 for blocking
        var mode: UInt32 = blocking ? 0 : 1
        ioctlsocket(SOCKET(socketFd), FIONBIO, &mode)
    }
    
    public func setReadTimeout(milliseconds value: UInt = 0) {
        var timeout = timeval()
        if value > 0 {
            timeout.tv_sec = Int32(Double(value / 1000))
            let uSecs = Int32(Double(value % 1000)) * 1000
            timeout.tv_usec = Int32(uSecs)
        }
        setsockopt (SOCKET(socketFd), SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.stride))
    }
    
    public func setWriteTimeout(milliseconds: UInt = 0) {
        var timeout = timeval()
        if milliseconds > 0 {
            timeout.tv_sec = Int32(milliseconds / 1000)
            let uSecs = (milliseconds % 1000) * 1000
            timeout.tv_usec = Int32(uSecs)
        }
        setsockopt (SOCKET(socketFd), SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.stride))
    }
    
    public func close() {
        guard socketFd >= 0 else { return }
        closesocket(SOCKET(socketFd))
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
            // TODO: MSG_NOSIGNAL?
            let bytesWritten = WinSDK.send(SOCKET(socketFd), cptr, Int32(endPtr - cptr), 0)
            
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
            cptr += Int(bytesWritten)
        }
        return cptr - startPtr
    }
    
    @discardableResult
    public func poll() -> Int {
        guard socketFd >= 0 else { return -1 }
        
        var readfds: fd_set = fd_set()
        readfds.fd_count = 1
        readfds.fd_array.0 = SOCKET(socketFd)
        
        var timeout = timeval()
        timeout.tv_sec = 0
        timeout.tv_usec = 0
        
        return Int(select(0, &readfds, nil, nil, &timeout))
    }
    
    @discardableResult
    public func recv(bytes: UnsafeMutablePointer<UInt8>?,
                     count: Int) -> Int {
        guard let bytes = bytes else { return -1 }
        guard socketFd >= 0 else { return -1 }
        let cptr = bytes
        let startPtr = bytes
        let endPtr = startPtr + count
        
        // TODO: MSG_NOSIGNAL?
        let bytesRead = WinSDK.recv(SOCKET(socketFd), cptr, Int32(endPtr - cptr), 0)
        
        if (bytesRead <= 0) {
            if bytesRead < 0 && errno == EWOULDBLOCK || errno == EAGAIN {
                return 0
            }
            self.close()
            return -1
        }
        return Int(bytesRead)
    }
    
    @discardableResult
    public func listen(address: String,
                       port: Int) -> Int {
        guard socketFd >= 0 else { return -1 }
        
        var one: Int32 = 1
        setsockopt(UInt64(socketFd), SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<timeval>.stride))
        
        var sockAddressIn = sockaddr_in()
        let sockAddrInSize = socklen_t(MemoryLayout<sockaddr_in>.size)
                                       
        sockAddressIn.sin_family = ADDRESS_FAMILY(AF_INET)
        inet_pton(AF_INET, address, &(sockAddressIn.sin_addr))
        sockAddressIn.sin_port = UInt16(clamping: port).bigEndian
        
        let result = withUnsafePointer(to: &sockAddressIn) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return bind(UInt64(socketFd), $0, sockAddrInSize)
            }
        }
                
        if result < 0 {
            return -1
        }
        
        let ret = WinSDK.listen(UInt64(socketFd), 128)
        if ret == SOCKET_ERROR {
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
                return Int32(WinSDK.accept(SOCKET(socketFd), $0, &sockAddrInSize))
            }
        }
        
        let socket = Socket(socketFd: clientFd,
                            blocking: blocking)
        
        let capacity = Int(INET6_ADDRSTRLEN)
        guard let scratch_ptr = malloc(capacity)?.bindMemory(to: CChar.self, capacity: capacity) else { return socket }
        
        _ = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                WinSDK.getpeername(SOCKET(clientFd), $0, &sockAddrInSize)
            }
        }

        if inet_ntop(Int32(clientAddr.sin_family), &clientAddr.sin_addr, scratch_ptr, Int(INET6_ADDRSTRLEN)) != nil {
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
                WinSDK.getpeername(SOCKET(socketFd), $0, &sockAddrInSize)
            }
        }

        if inet_ntop(Int32(clientAddr.sin_family), &clientAddr.sin_addr, scratch_ptr, Int(INET6_ADDRSTRLEN)) != nil {
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
        sockAddressIn.sin_family = ADDRESS_FAMILY(AF_INET)
        inet_pton(AF_INET, address, &(sockAddressIn.sin_addr))
        sockAddressIn.sin_port = UInt16(clamping: port).bigEndian
        
        let _ = withUnsafePointer(to: &sockAddressIn) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return connect(SOCKET(socketFd), $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return 0
    }
}

#endif
