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
    public static let shared = DNS()
    private override init() {
        super.init()
    }

    internal func _beResolve(domain: String) -> [String] {
        guard let hp = gethostbyname(domain) else { return [] }
        
        var addresses: [String] = []
        
        let capacity = Int(INET6_ADDRSTRLEN)
        guard let scratch_ptr = malloc(capacity)?.bindMemory(to: CChar.self, capacity: capacity) else { return [] }
        
        defer { free(scratch_ptr) }

        let inetType = hp.pointee.h_addrtype
        switch inetType {
        case AF_INET, AF_INET6:
            guard let addr_list_ptr = hp.pointee.h_addr_list else { return [] }
            
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
        
        return addresses
    }
    
    
}
