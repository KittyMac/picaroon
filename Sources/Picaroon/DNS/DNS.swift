import Foundation
import Flynn
import Hitch

import Foundation

#if canImport(Glibc)
private let gethostbyname = Glibc.gethostbyname
private let inet_ntop = Glibc.inet_ntop
#endif
#if canImport(Darwin)
private let gethostbyname = Darwin.gethostbyname
private let inet_ntop = Darwin.inet_ntop
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
    
    public static func resolve(domain: String) -> DNS.Results {
        guard let hp = gethostbyname(domain) else { return DNS.Results() }
        
        var aliases: [String] = []
        var addresses: [String] = []
        
        let capacity = Int(INET6_ADDRSTRLEN)
        guard let scratch_ptr = malloc(capacity)?.bindMemory(to: CChar.self, capacity: capacity) else { return DNS.Results() }
        
        defer { free(scratch_ptr) }
        
        
        var idx = 0
        while true {
            guard let alias_ptr = hp.pointee.h_aliases[idx] else { break }
            guard let alias = String(utf8String: alias_ptr) else { break }
            aliases.append(alias)
            idx += 1
        }

        let inetType = hp.pointee.h_addrtype
        switch inetType {
        case AF_INET, AF_INET6:
            guard let addr_list_ptr = hp.pointee.h_addr_list else { return DNS.Results() }
            
            var idx = 0
            while true {
                guard let addr_ptr = addr_list_ptr[idx] else { break }
                if inet_ntop(inetType, addr_ptr, scratch_ptr, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let count = strnlen(scratch_ptr, Int(INET6_ADDRSTRLEN))
                    scratch_ptr.withMemoryRebound(to: UInt8.self, capacity: count) { hitchPtr in
                        addresses.append(
                            Hitch(bytes: hitchPtr, offset: 0, count: count).toString()
                        )
                    }
                }
                idx += MemoryLayout.stride(ofValue: in_addr.self)
            }
            break
        case AF_INET6:
            break
        default:
            break
        }
        
        // gethostbyname() is old and does not return the aliases consistenty. Flynn provides res_query
        // code to look these up as well.
        if let cname = Flynn.dns_resolve_cname(domain: domain) {
            aliases.append(cname)
        }
        if let txt = Flynn.dns_resolve_txt(domain: domain) {
            aliases.append(txt)
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
