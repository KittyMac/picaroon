import Foundation
import Flynn
import Hitch

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if !os(Windows)

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#else
#error("Unknown platform")
#endif

public class DNS: Actor {
    public struct Results {
        public let aliases: [String]
        public let addresses: [String]
        
        public init() {
            aliases = []
            addresses = []
        }
        
        public init(aliases: [String],
                    addresses: [String]) {
            self.aliases = aliases
            self.addresses = addresses
        }
    }
    
    public static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }

                guard let interface = ptr?.pointee else { return "" }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

                    // wifi = ["en0"]
                    // wired = ["en2", "en3", "en4"]
                    // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]

                    let name: String = String(cString: (interface.ifa_name))
                    if  name == "en0" || name == "en2" || name == "en3" || name == "en4" || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        
                        getnameinfo(interface.ifa_addr,
                                    socklen_t(MemoryLayout<sockaddr>.size),
                                    &hostname,
                                    socklen_t(hostname.count),
                                    nil,
                                    0,
                                    NI_NUMERICHOST)

                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
    
    public static func resolve(domain: String) -> DNS.Results {
        // NOTE: gethostbyname is not very safe on Linux (we've observed multiple memory crashes
        // related to aliases, so we are using gethostbyname_r instead
#if os(Linux)
        var result: hostent = hostent()
        var resultPointer: UnsafeMutablePointer<hostent>? = UnsafeMutablePointer<hostent>(mutating: nil)
        let bufferSize = 4096
        var buffer = [CChar](repeating: 0, count: bufferSize)
        var hErrno: Int32 = 0

        let status = gethostbyname_r(domain, &result, &buffer, bufferSize, &resultPointer, &hErrno)
        guard status == 0, let hp = resultPointer else { return DNS.Results() }
#else
        guard let hp = gethostbyname(domain) else { return DNS.Results() }
#endif
        
        guard hp.pointee.h_addrtype == AF_INET, hp.pointee.h_length > 0 else { return DNS.Results() }
        
        var aliases: [String] = []
        var addresses: [String] = []
        
        let capacity = Int(INET6_ADDRSTRLEN)
        guard let scratch_ptr = malloc(capacity)?.bindMemory(to: CChar.self, capacity: capacity) else { return DNS.Results() }
        
        defer { free(scratch_ptr) }
        
        
        var aliasPointer = hp.pointee.h_aliases
        while let alias = aliasPointer?.pointee {
            let aliasString = String(cString: alias)
            aliases.append(aliasString)
            aliasPointer = aliasPointer?.successor()
        }

        let inetType = hp.pointee.h_addrtype
        switch inetType {
        case AF_INET, AF_INET6:
            guard let addr_list_ptr = hp.pointee.h_addr_list else { return DNS.Results() }
            
            var idx = 0
            while true {
                guard let addr_ptr = addr_list_ptr[idx] else { break }
                if inet_ntop(inetType, addr_ptr, scratch_ptr, socklen_t(INET6_ADDRSTRLEN)) != nil {
                    let count = strnlen(scratch_ptr, Int(INET6_ADDRSTRLEN))
                    scratch_ptr.withMemoryRebound(to: UInt8.self, capacity: count) { hitchPtr in
                        addresses.append(
                            Hitch(bytes: hitchPtr, offset: 0, count: count).toString()
                        )
                    }
                }
                idx += 1
            }
            break
        default:
            break
        }
        
        if aliases.isEmpty {
            // gethostbyname() is old and does not return the aliases consistenty. Flynn provides res_query
            // code to look these up as well.
            if let cname = Flynn.dns_resolve_cname(domain: domain) {
                aliases.append(cname)
            }
            if let txt = Flynn.dns_resolve_txt(domain: domain) {
                aliases.append(txt)
            }
        }
        
        return DNS.Results(aliases: aliases,
                           addresses: addresses)
    }
    
    public static func resolve(url: URL) -> DNS.Results {
        guard let host = url.host else { return DNS.Results() }
        return Self.resolve(domain: host)
    }
    
    
    public static let shared = DNS()
    private override init() {
        super.init()
    }

    internal func _beResolve(domain: String) -> DNS.Results {
        return Self.resolve(domain: domain)
    }
    
    internal func _beResolve(url: URL) -> DNS.Results {
        guard let host = url.host else { return DNS.Results() }
        return Self.resolve(domain: host)
    }
    
    
}

#endif
