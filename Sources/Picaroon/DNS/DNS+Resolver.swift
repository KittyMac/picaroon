import Foundation
import Flynn

// Shared, platform independent front end for DNS lookups.
//
// The system resolver (gethostbyname / gethostbyname_r / res_query) is not
// cancellable. Once it is sitting in a recvfrom() waiting on a nameserver there
// is nothing this side of the call can do to bring it back; it returns when it
// returns, which under a black-holed nameserver can be tens of seconds or, on
// some configurations, never. Two consequences follow, and this file exists to
// contain both of them:
//
// 1. The blocking call must never run on DispatchQueue.global(). A wedged
//    resolver permanently consumes a thread from the pool that URLSession,
//    Flynn and everything else in the process shares. Enough of them and the
//    pool is gone.
//
// 2. Timing out the *caller* is not the same as timing out the *lookup*.
//    Starting a fresh lookup every time a caller gives up accumulates stuck
//    threads without bound, which is the failure mode that motivated this.
//
// So: at most one lookup thread per domain at a time, a hard ceiling on how
// many lookups can be outstanding across all domains, and a cache in front of
// the whole thing so the steady state never reaches the resolver at all.

fileprivate final class Resolver {
    static let shared = Resolver()

    private struct CacheEntry {
        let results: DNS.Results
        let expiresAt: TimeInterval
    }

    /// One caller waiting on one lookup. Reference type so that the lookup
    /// thread and the caller's deadline can race to retire it exactly once.
    fileprivate final class Waiter {
        let callback: (DNS.Results) -> ()
        var isFinished = false

        init(_ callback: @escaping (DNS.Results) -> ()) {
            self.callback = callback
        }
    }

    /// How long a good answer is reused. Deliberately not the record's TTL;
    /// we are protecting the process from the resolver, not implementing one.
    private let successTTL: TimeInterval = 5 * 60

    /// Failures are cached too, briefly, so that a down nameserver produces one
    /// slow lookup every 30s instead of one per request.
    private let failureTTL: TimeInterval = 30

    /// Ceiling on simultaneously outstanding lookups (ie. worst case number of
    /// wedged threads this class can be responsible for).
    private let maxConcurrentLookups = 8

    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]
    private var waiters: [String: [Waiter]] = [:]
    private var lookupCount = 0

    private func now() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    func cached(domain: String) -> DNS.Results? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[domain],
              entry.expiresAt > now() else { return nil }
        return entry.results
    }

    /// Never blocks the calling thread.
    ///
    /// timeoutSeconds == 0 means "call me back whenever the resolver answers",
    /// which is what the synchronous wrapper wants (it enforces its own
    /// deadline with a semaphore and must not depend on the Flynn scheduler,
    /// since the thread it is blocking may well be a scheduler thread).
    func resolve(domain: String,
                 timeoutSeconds: Double,
                 _ returnCallback: @escaping (DNS.Results) -> ()) {
        if let results = cached(domain: domain) {
            return returnCallback(results)
        }

        let waiter = Waiter(returnCallback)

        lock.lock()

        if waiters[domain] != nil {
            // a lookup for this domain is already running: ride along on it
            // instead of starting a second one. Note this is keyed on presence,
            // not on count - an empty array still means "in flight, everyone
            // who asked has since timed out".
            waiters[domain]?.append(waiter)
            lock.unlock()
        } else if lookupCount >= maxConcurrentLookups {
            // saturated, and almost certainly with wedged lookups rather than
            // slow ones. Fail fast rather than stacking up more threads.
            lock.unlock()
            return returnCallback(DNS.Results())
        } else {
            waiters[domain] = [waiter]
            lookupCount += 1
            lock.unlock()

            // A dedicated thread, NOT the global queue: see the note at the top
            // of this file.
            let thread = Thread {
                Flynn.threadSetName("Picaroon.DNS")
                let results = DNS.resolveBlocking(domain: domain)
                Resolver.shared.finish(domain: domain, results: results)
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }

        guard timeoutSeconds > 0 else { return }

        // The lookup cannot be cancelled, but this caller's interest in it can.
        // If nothing has come back by the deadline the waiter is retired with an
        // empty result; the lookup keeps running and whoever asks next gets the
        // answer out of the cache for free.
        Flynn.Timer(timeInterval: timeoutSeconds,
                    immediate: false,
                    repeats: false,
                    Flynn.any) { [weak self] _ in
            guard let self = self else { return }
            guard self.retire(waiter: waiter, domain: domain) else { return }
            waiter.callback(DNS.Results())
        }
    }

    /// Returns true if this call is the one that retired the waiter, ie. the
    /// caller now owns invoking its callback.
    private func retire(waiter: Waiter, domain: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard waiter.isFinished == false else { return false }
        waiter.isFinished = true
        waiters[domain]?.removeAll { $0 === waiter }
        return true
    }

    private func finish(domain: String, results: DNS.Results) {
        let ttl = results.addresses.isEmpty ? failureTTL : successTTL

        lock.lock()
        cache[domain] = CacheEntry(results: results,
                                   expiresAt: now() + ttl)
        let pending = (waiters.removeValue(forKey: domain) ?? []).filter { $0.isFinished == false }
        for waiter in pending {
            waiter.isFinished = true
        }
        lookupCount -= 1
        lock.unlock()

        // deliberately outside the lock: these callbacks are caller supplied
        for waiter in pending {
            waiter.callback(results)
        }
    }
}

extension DNS {

    /// Resolve without blocking the calling thread. The callback is invoked
    /// once, either with the resolver's answer or - after timeoutSeconds - with
    /// an empty result.
    public static func resolve(domain: String,
                               timeoutSeconds: Double = 5.0,
                               _ returnCallback: @escaping (DNS.Results) -> ()) {
        Resolver.shared.resolve(domain: domain,
                                timeoutSeconds: timeoutSeconds,
                                returnCallback)
    }

    public static func resolve(url: URL,
                               timeoutSeconds: Double = 5.0,
                               _ returnCallback: @escaping (DNS.Results) -> ()) {
        guard let host = url.host else { return returnCallback(DNS.Results()) }
        resolve(domain: host,
                timeoutSeconds: timeoutSeconds,
                returnCallback)
    }

    /// Blocking resolve, bounded by timeoutSeconds.
    ///
    /// Prefer the callback version. This exists for callers which are already
    /// on a thread they are allowed to park (and note that a Flynn scheduler
    /// thread is not one of those). It answers from cache without touching the
    /// resolver whenever it can, and when it does miss, the lookup it starts is
    /// shared with every other caller asking for the same domain.
    public static func resolve(domain: String,
                               timeoutSeconds: Double = 5.0) -> DNS.Results {
        if let results = Resolver.shared.cached(domain: domain) {
            return results
        }

        final class Box {
            var results = DNS.Results()
        }

        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)

        // timeoutSeconds: 0 - the deadline below is ours to enforce. Handing it
        // to Flynn.Timer instead would deadlock whenever every scheduler thread
        // is parked inside this very function.
        resolve(domain: domain, timeoutSeconds: 0) { results in
            box.results = results
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeoutSeconds) == .success else {
            return DNS.Results()
        }
        return box.results
    }

    public static func resolve(url: URL,
                               timeoutSeconds: Double = 5.0) -> DNS.Results {
        guard let host = url.host else { return DNS.Results() }
        return resolve(domain: host, timeoutSeconds: timeoutSeconds)
    }
}
