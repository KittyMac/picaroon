import Foundation
import Flynn
import Hitch

// NTP time is a cache, not a query.
//
// date() is called on the request signing path (see AWS/S3/*.swift), which means
// it is called on Flynn actor threads. It must therefore never block: the sync
// it needs performs a DNS lookup and a UDP round trip, either of which can take
// seconds, or - on a network which black holes udp/123, which is most captive
// portals and a fair number of mobile carriers - can take as long as the socket
// read timeout allows. Parking a scheduler thread there stops every actor that
// thread was going to run.
//
// So date() answers immediately from whatever offset we last obtained, and
// starts a refresh on its own dedicated thread if that offset has gone stale.
// The refresh updates the offset for whoever asks next.

public class NTP {
    private static let epochDelta = 2208988800.0
    private static let epochRolloverDelta = pow(2.0, 32.0) - epochDelta
    
    private static let ntpDomain = "pool.ntp.org"
    private static let ntpPort = 123
    private static let timeoutMilliseconds: UInt = 5000
    
    /// How long a good offset is used before we go looking for a fresh one.
    private static let syncInterval: TimeInterval = 5 * 60
    
    /// Backoff bounds after a failed sync. Note this replaces the old `disabled`
    /// flag, which permanently gave up on the first dropped udp packet.
    private static let minRetryInterval: TimeInterval = 60
    private static let maxRetryInterval: TimeInterval = 60 * 60
    
    /// Guards every mutable static below, and is broadcast on whenever a sync
    /// finishes so that warm() can wake up.
    private static let condition = NSCondition()
    private static var ntpOffset: TimeInterval? = nil
    private static var nextSyncDate = Date.distantPast
    private static var isSyncing = false
    private static var failureCount = 0
    
    // MARK: - public
    
    /// The current time, corrected by the most recent NTP offset we managed to
    /// obtain. Never blocks; safe to call from an actor.
    ///
    /// Before the first successful sync this returns the device clock, and
    /// kicks off the sync which will correct subsequent calls. Callers who need
    /// a corrected time up front should call warm() once at startup.
    public static func date() -> Date {
        guard let offset = offset() else { return Date() }
        return Date(timeIntervalSinceNow: offset)
    }
    
    /// True once at least one sync has succeeded.
    public static var isSynchronized: Bool {
        condition.lock()
        defer { condition.unlock() }
        return ntpOffset != nil
    }
    
    /// Discard the refresh schedule and sync again as soon as possible. Called
    /// from the S3 paths when a request is rejected in a way that suggests our
    /// clock is wrong. Never blocks; the existing offset stays in use until the
    /// refresh lands.
    public static func reset() {
        condition.lock()
        failureCount = 0
        nextSyncDate = Date.distantPast
        let shouldStart = beginSyncLocked()
        condition.unlock()
        
        if shouldStart {
            startSyncThread()
        }
    }
    
    /// Blocks the calling thread until an offset is available, or until
    /// timeoutSeconds elapses. Returns whether we have an offset.
    ///
    /// Intended to be called once during startup, from a thread you are allowed
    /// to park. Do NOT call this from an actor - use date() there.
    @discardableResult
    public static func warm(timeoutSeconds: Double = 5.0) -> Bool {
        _ = offset()
        
        let deadline = Date(timeIntervalSinceNow: timeoutSeconds)
        
        condition.lock()
        defer { condition.unlock() }
        while ntpOffset == nil && Date() < deadline {
            guard condition.wait(until: deadline) else { break }
        }
        return ntpOffset != nil
    }
    
    // MARK: - private
    
    /// Returns the cached offset, starting a refresh if it has gone stale.
    private static func offset() -> TimeInterval? {
        condition.lock()
        let offset = ntpOffset
        let shouldStart = Date() >= nextSyncDate && beginSyncLocked()
        condition.unlock()
        
        if shouldStart {
            startSyncThread()
        }
        return offset
    }
    
    /// Claims the right to run a sync. Must be called with the condition held;
    /// returns true if the caller is now responsible for starting the thread.
    private static func beginSyncLocked() -> Bool {
        guard isSyncing == false else { return false }
        isSyncing = true
        return true
    }
    
    private static func startSyncThread() {
        // A dedicated thread rather than DispatchQueue.global(): this work can
        // park for the full socket timeout, and we must not spend a thread from
        // the pool the rest of the process shares to do it.
        let thread = Thread {
            Flynn.threadSetName("Picaroon.NTP")
            finish(offset: performSync(domain: ntpDomain))
        }
        thread.stackSize = 512 * 1024
        thread.start()
    }
    
    private static func finish(offset: TimeInterval?) {
        let now = Date()
        
        condition.lock()
        if let offset = offset {
            ntpOffset = offset
            failureCount = 0
            nextSyncDate = now.addingTimeInterval(syncInterval)
        } else {
            failureCount += 1
            // Exponential backoff rather than giving up forever: a single lost
            // udp packet should not cost us ntp for the life of the process.
            let backoff = min(minRetryInterval * pow(2.0, Double(failureCount - 1)),
                              maxRetryInterval)
            nextSyncDate = now.addingTimeInterval(backoff)
        }
        isSyncing = false
        condition.broadcast()
        condition.unlock()
    }
    
    /// The blocking part. Runs only on the thread started by startSyncThread(),
    /// and touches no shared state.
    private static func performSync(domain: String) -> TimeInterval? {
        let dns = DNS.resolve(domain: domain)
        guard let address = dns.addresses.first else { return nil }
        
        guard let socket = Socket(udp: true) else { return nil }
        defer { socket.close() }
        
        socket.setWriteTimeout(milliseconds: timeoutMilliseconds)
        socket.setReadTimeout(milliseconds: timeoutMilliseconds)
        
        guard socket.connectTo(address: address, port: ntpPort) == 0 else { return nil }
        
        let msg = Hitch(garbage: 48)
        guard let raw = msg.mutableRaw() else { return nil }
        
        for idx in 0..<48 {
            raw[idx] = 0
        }
        raw[0] = 0x1B
        
        guard socket.send(hitch: msg) > 0 else { return nil }
        guard socket.recv(bytes: raw, count: 48) > 0 else { return nil }
        
        var time: UInt64 = 0
        memcpy(&time, raw + 40, 8)
        time = UInt64(bigEndian: time)
        
        let needsRollOver = (time & 0x8000000000000000) == 0
        let delta = needsRollOver ? epochRolloverDelta : -epochDelta
        let integer = TimeInterval(time >> 32)
        let decimal = TimeInterval(time & 0xffffffff) / 4294967296.0
        return TimeInterval(integer + delta + decimal) - Date().timeIntervalSince1970
    }
}
