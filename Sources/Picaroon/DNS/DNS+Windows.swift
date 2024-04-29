import Foundation
import Flynn
import Hitch

import Foundation

#if os(Windows)

import WinSDK

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
        guard checkWAS() else { return DNS.Results() }
        
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
        switch Int32(inetType) {
        case AF_INET, AF_INET6:
            guard let addr_list_ptr = hp.pointee.h_addr_list else { return DNS.Results() }
            
            var idx = 0
            while true {
                guard let addr_ptr = addr_list_ptr[idx] else { break }
                if inet_ntop(Int32(inetType), addr_ptr, scratch_ptr, Int(socklen_t(INET6_ADDRSTRLEN))) != nil {
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
