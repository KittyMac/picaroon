import Foundation
import Flynn
import Hitch

import Foundation

public class NTP {
    private static let epochDelta = 2208988800.0
    private static let epochRolloverDelta = pow(2.0, 32.0) - epochDelta
    
    private static var didAttemptSyncOnce: Bool = false
    private static var ntpOffset: TimeInterval? = nil
    
    private static func sync(domain: String = "pool.ntp.org") {
        let dns = DNS.resolve(domain: domain)
        guard let address = dns.addresses.first else { return }
        
        guard let socket = Socket(udp: true) else { return }
        
        guard socket.connectTo(address: address, port: 123) == 0 else { return }
        
        let msg = Hitch(garbage: 48)
        guard let raw = msg.mutableRaw() else { return }
        
        for idx in 0..<48 {
            raw[idx] = 0
        }
        raw[0] = 0x1B
        guard socket.send(hitch: msg) > 0 else { return }
        
        guard socket.recv(bytes: raw, count: 48) > 0 else { return }
        
        let time = UInt64((raw + 40).withMemoryRebound(to: UInt64.self, capacity: 1) {
            $0.pointee
        }.bigEndian)
            
        let needsRollOver = time & 0x8000000000000000 == 0
        let delta = needsRollOver ? epochRolloverDelta : -epochDelta
        let integer = TimeInterval(time >> 32)
        let decimal = TimeInterval(time & 0xffffffff) / 4294967296.0
        ntpOffset = Date().timeIntervalSince1970 - TimeInterval(integer + delta + decimal)
    }
    
    public static func date() -> Date {
        if (didAttemptSyncOnce == false) {
            didAttemptSyncOnce = true
            sync()
        }
        guard let ntpOffset = ntpOffset else { return Date() }
        return Date(timeIntervalSinceNow: ntpOffset)
    }
    
}
