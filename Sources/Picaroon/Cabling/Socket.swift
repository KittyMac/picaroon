import Foundation
import Flynn
import Hitch

#if !os(Windows)

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Glibc)
import Glibc
private let posix_close = Glibc.close
private let posix_send = Glibc.send
private let posix_recv = Glibc.recv
private let posix_poll = Glibc.poll
private let posix_listen = Glibc.listen
private let posix_accept = Glibc.accept
#elseif canImport(Darwin)
import Darwin
private let posix_close = Darwin.close
private let posix_send = Darwin.send
private let posix_recv = Darwin.recv
private let posix_poll = Darwin.poll
private let posix_listen = Darwin.listen
private let posix_accept = Darwin.accept
#elseif canImport(Android)
import Android
private let posix_close = Android.close
private let posix_send = Android.send
private let posix_recv = Android.recv
private let posix_poll = Android.poll
private let posix_listen = Android.listen
private let posix_accept = Android.accept
#else
#error("Unknown platform")
#endif



public class Socket {

    private let lock = NSLock()

    private var lockedSocketFd: Int32
    private var lockedUseCount = 0

    private let closing = AtomicBool(false)

    public init?(socketFd: Int32,
                 blocking: Bool = true) {
        lockedSocketFd = socketFd

        guard socketFd >= 0 else { return nil }

        applyOptions(blocking: blocking)
    }

    public init?(udp: Bool) {
        #if os(Android)
        let newFd = socket(AF_INET, SOCK_DGRAM, 0)
        #elseif os(Linux)
        let newFd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        #else
        let newFd = socket(AF_INET, SOCK_DGRAM, 0)
        #endif

        lockedSocketFd = newFd

        guard newFd >= 0 else { return nil }

        setReadTimeout(milliseconds: 2000)
        setWriteTimeout(milliseconds: 2000)
    }

    public init?(blocking: Bool = true) {
        #if os(Android)
        let newFd: Int32
        if blocking {
            newFd = socket(AF_INET, SOCK_STREAM, 0)
        } else {
            newFd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0)
        }
        #elseif os(Linux)
        let newFd: Int32
        if blocking {
            newFd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        } else {
            newFd = socket(AF_INET, Int32(SOCK_STREAM.rawValue | SOCK_NONBLOCK.rawValue), 0)
        }
        #else
        let newFd = socket(AF_INET, SOCK_STREAM, 0)
        #endif

        lockedSocketFd = newFd

        guard newFd >= 0 else { return nil }

        applyOptions(blocking: blocking)
    }

    deinit {
        self.close()
    }

    // MARK: - Descriptor lifetime

    private func acquireFd() -> Int32? {
        // Fast reject: monotonic, so true here is final and needs no lock.
        if closing.value { return nil }

        lock.lock()
        defer { lock.unlock() }

        // The reading above may have been stale; this one decides.
        guard closing.value == false,
              lockedSocketFd >= 0 else { return nil }

        lockedUseCount += 1
        return lockedSocketFd
    }

    private func releaseFd() {
        lock.lock()
        lockedUseCount -= 1
        let fd = takeFdIfDrainedLocked()
        lock.unlock()

        // Deliberately outside the lock: posix_close can block on a lingering
        // socket, and the watch thread wants this lock every 50ms.
        if fd >= 0 {
            _ = posix_close(fd)
        }
    }

    private func takeFdIfDrainedLocked() -> Int32 {
        guard closing.value,
              lockedUseCount == 0 else { return -1 }

        let fd = lockedSocketFd
        lockedSocketFd = -1
        return fd
    }

    private func applyOptions(blocking: Bool) {
        #if os(Linux) || os(Android)
        #else
        // Runs from init before this Socket has been published to any other
        // thread, so the descriptor is read directly rather than acquired.
        let fd = lockedSocketFd
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<timeval>.stride))

        let flags = fcntl(fd, F_GETFL)
        if blocking {
            _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        } else {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        #endif
    }
    
    #if os(Android)
    private static let soRcvTimeo: Int32 = 20 // SO_RCVTIMEO_OLD
    private static let soSndTimeo: Int32 = 21 // SO_SNDTIMEO_OLD
    #else
    private static let soRcvTimeo: Int32 = SO_RCVTIMEO
    private static let soSndTimeo: Int32 = SO_SNDTIMEO
    #endif
    
    @discardableResult
    public func setReadTimeout(milliseconds value: UInt = 0) -> Bool {
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
        
        guard let fd = acquireFd() else { return false }
        defer { releaseFd() }

        guard setsockopt(fd, SOL_SOCKET, Self.soRcvTimeo, &timeout, socklen_t(MemoryLayout<timeval>.stride)) == 0 else {
            Flynn.syslog("TAG", "warning: failed to set read timeout of \(value)ms on socket \(fd), errno \(errno)")
            return false
        }
        return true
    }
    
    @discardableResult
    public func setWriteTimeout(milliseconds: UInt = 0) -> Bool {
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
        
        guard let fd = acquireFd() else { return false }
        defer { releaseFd() }

        guard setsockopt(fd, SOL_SOCKET, Self.soSndTimeo, &timeout, socklen_t(MemoryLayout<timeval>.stride)) == 0 else {
            Flynn.syslog("TAG", "warning: failed to set write timeout of \(milliseconds)ms on socket \(fd), errno \(errno)")
            return false
        }
        return true
    }
    
    public func close() {
        guard closing.exchange(true) == false else { return }

        lock.lock()

        let live = lockedSocketFd
        if live >= 0 {
            _ = shutdown(live, Int32(SHUT_RDWR))
        }

        let fd = takeFdIfDrainedLocked()
        lock.unlock()

        if fd >= 0 {
            _ = posix_close(fd)
        }
    }

    public func isClosed() -> Bool {
        return closing.value
    }

    public func fd() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return lockedSocketFd
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
    public func send(chunked bytes: UnsafePointer<UInt8>?,
                     count: Int) -> Int {
        guard let bytes = bytes else { return -1 }
        guard acquireFd() != nil else { return -1 }
        defer { releaseFd() }

        var cptr = bytes
        let startPtr = bytes
        let endPtr = startPtr + count
        
        let hexCountHitch = Hitch(capacity: 128)
        guard let hexCountHitchRaw = hexCountHitch.mutableRaw() else { self.close(); return -1 }
        
        let newLineHitch = Hitch(string: "\r\n")
        guard let newLineHitchRaw = newLineHitch.raw() else { self.close(); return -1 }
        
        let endHitch = Hitch(string: "0\r\n\r\n")
        guard let endHitchRaw = endHitch.raw() else { self.close(); return -1 }

        while endPtr - cptr > 0 {
            let chunkSize = min(1024 * 1024, endPtr - cptr)
            
            var idx = hexCountHitch.capacity-1
            
            hexCountHitchRaw[idx] = .newLine
            idx -= 1
            hexCountHitchRaw[idx] = .carriageReturn
            idx -= 1
            
            var hexChunkSize = chunkSize
            while hexChunkSize > 0 {
                hexCountHitchRaw[idx] = hex2(UInt32(hexChunkSize & 0xF))
                hexChunkSize >>= 4
                idx -= 1
            }
            idx += 1
            
            guard send(bytes: hexCountHitchRaw + idx, count: hexCountHitch.capacity - idx) == hexCountHitch.capacity - idx else { self.close(); return -1 }
            
            guard send(bytes: cptr, count: chunkSize) == chunkSize else { self.close(); return -1 }
            
            guard send(bytes: newLineHitchRaw, count: newLineHitch.count) == newLineHitch.count else { self.close(); return -1 }

            cptr += chunkSize
        }
        
        guard send(bytes: endHitchRaw, count: endHitch.count) == endHitch.count else { self.close(); return -1 }

        
        return cptr - startPtr
    }
    
    @discardableResult
    public func send(bytes: UnsafePointer<UInt8>?,
                     count: Int) -> Int {
        guard let bytes = bytes else { return -1 }
        guard let fd = acquireFd() else { return -1 }
        defer { releaseFd() }

        var cptr = bytes
        let startPtr = bytes
        let endPtr = startPtr + count
        
        while cptr < endPtr {
            let bytesWritten = posix_send(fd, cptr, endPtr - cptr, Int32(MSG_NOSIGNAL))
            
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
        guard let fd = acquireFd() else { return -1 }
        defer { releaseFd() }

        let nfds: nfds_t = 1
        let timeout: Int32 = 0
        var fds: pollfd = pollfd(fd: fd,
                                 events: Int16(POLLIN),
                                 revents: 0)
        return Int(posix_poll(&fds, nfds, timeout))
    }
    
    @discardableResult
    public func recv(bytes: UnsafeMutablePointer<UInt8>?,
                     count: Int) -> Int {
        guard let bytes = bytes else { return -1 }
        guard let fd = acquireFd() else { return -1 }
        defer { releaseFd() }

        let cptr = bytes
        let startPtr = bytes
        let endPtr = startPtr + count
                            
        let bytesRead = posix_recv(fd, cptr, endPtr - cptr, Int32(MSG_NOSIGNAL))
        
        if (bytesRead <= 0) {
            if bytesRead < 0 && (errno == EWOULDBLOCK || errno == EAGAIN) {
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
        guard let fd = acquireFd() else { return -1 }
        defer { releaseFd() }

        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<timeval>.stride))
        
        var sockAddressIn = sockaddr_in()
        let sockAddrInSize = socklen_t(MemoryLayout<sockaddr_in>.size)
                                       
        sockAddressIn.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, address, &(sockAddressIn.sin_addr))
        sockAddressIn.sin_port = UInt16(clamping: port).bigEndian
        
        let result = withUnsafePointer(to: &sockAddressIn) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return bind(fd, $0, sockAddrInSize)
            }
        }
                
        if result < 0 {
            return -1
        }
        
        let ret = posix_listen(fd, 128)
        if ret < 0 {
            self.close()
            return -1
        }
        
        return 0
    }
    
    @discardableResult
    public func accept(blocking: Bool = true, clientAddress: inout String) -> Socket? {
        clientAddress = ""
        
        guard let fd = acquireFd() else { return nil }
        defer { releaseFd() }

        var clientAddr = sockaddr_in()
        var sockAddrInSize = socklen_t(MemoryLayout<sockaddr_in>.size)

        let clientFd: Int32 = withUnsafeMutablePointer(to: &clientAddr) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return posix_accept(fd, $0, &sockAddrInSize)
            }
        }
        
        let socket = Socket(socketFd: clientFd,
                            blocking: blocking)
        
        let capacity = Int(INET6_ADDRSTRLEN)
        guard let scratch_ptr = malloc(capacity)?.bindMemory(to: CChar.self, capacity: capacity) else { return socket }
        defer { free(scratch_ptr) }
        
        _ = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getpeername(clientFd, $0, &sockAddrInSize)
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
        
        guard let fd = acquireFd() else { return clientAddress }
        defer { releaseFd() }

        var clientAddr = sockaddr_in()
        var sockAddrInSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let capacity = Int(INET6_ADDRSTRLEN)
        guard let scratch_ptr = malloc(capacity)?.bindMemory(to: CChar.self, capacity: capacity) else { return clientAddress }
        
        _ = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getpeername(fd, $0, &sockAddrInSize)
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
        guard let fd = acquireFd() else { return -1 }
        defer { releaseFd() }

        var sockAddressIn = sockaddr_in()
        sockAddressIn.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, address, &(sockAddressIn.sin_addr))
        sockAddressIn.sin_port = UInt16(clamping: port).bigEndian
                        
        let _ = withUnsafePointer(to: &sockAddressIn) {
            return $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                return connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return 0
    }
}

#endif
