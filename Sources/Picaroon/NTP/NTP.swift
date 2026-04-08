import Foundation
import Flynn
import Hitch

import Foundation

public class NTP {
    private static let epochDelta = 2208988800.0
    private static let epochRolloverDelta = pow(2.0, 32.0) - epochDelta
    
    private static var ntpOffset: TimeInterval? = nil
    
    private static var lastSyncDate = Date.distantPast
    private static let lock = NSLock()
    private static var disabled = false
    
    private static func sync(domain: String = "pool.ntp.org") -> TimeInterval? {
        guard lock.try() == true else { return nil }
        defer { lock.unlock() }

        guard disabled == false else { return ntpOffset }
        guard abs(lastSyncDate.timeIntervalSinceNow) > 5 * 60 else { return ntpOffset }
        
        lastSyncDate = Date()
        
        let dns = DNS.resolve(domain: domain)
        guard let address = dns.addresses.first else { return ntpOffset }
        
        guard let socket = Socket(udp: true) else { return ntpOffset }
        
        socket.setWriteTimeout(milliseconds: 5000)
        socket.setReadTimeout(milliseconds: 5000)
        
        guard socket.connectTo(address: address, port: 123) == 0 else {
            disabled = true
            return ntpOffset
        }
        
        let msg = Hitch(garbage: 48)
        guard let raw = msg.mutableRaw() else { return ntpOffset }
        
        for idx in 0..<48 {
            raw[idx] = 0
        }
        raw[0] = 0x1B
        guard socket.send(hitch: msg) > 0 else {
            disabled = true
            return ntpOffset
        }
        
        guard socket.recv(bytes: raw, count: 48) > 0 else {
            disabled = true
            return ntpOffset
        }
        
        var time: UInt64 = 0
        memcpy(&time, raw + 40, 8)
        time = UInt64(bigEndian: time)
            
        let needsRollOver = (time & 0x8000000000000000) == 0
        let delta = needsRollOver ? epochRolloverDelta : -epochDelta
        let integer = TimeInterval(time >> 32)
        let decimal = TimeInterval(time & 0xffffffff) / 4294967296.0
        ntpOffset = TimeInterval(integer + delta + decimal) - Date().timeIntervalSince1970
        
        socket.close()
        
        return ntpOffset
    }
    
    public static func reset() {
        lastSyncDate = Date.distantPast
    }
    
    public static func date() -> Date {
        guard let offset = sync() else { return Date() }
        return Date(timeIntervalSinceNow: offset)
    }
    
}
