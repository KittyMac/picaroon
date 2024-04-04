import Foundation
import Flynn
import Hitch

import Foundation

#if os(Windows)

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
        return DNS.Results()
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
