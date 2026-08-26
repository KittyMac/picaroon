import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supply the certificate authority bundle used to validate TLS connections.
///
/// Motivating case: on Android there is no system CA bundle at a path libcurl knows
/// about, so the bundle has to be shipped with the app. Writing it to disk and
/// pointing libcurl at the file has two failure modes seen in practice:
///
///   1. `Context.getCacheDir()` may be emptied by the OS at any time, without
///      notice, which produces an intermittent
///      "error setting certificate file: .../cache/cacert.pem".
///   2. Reading the path from the environment on every request races with any
///      `setenv()` elsewhere in the process, since `getenv()` returns a pointer
///      into the environment block that `setenv()` may free.
///
/// Passing the bytes directly avoids both. Where the libcurl in use supports it
/// (7.77+), they are handed over with `CURLOPT_CAINFO_BLOB` and never touch the
/// filesystem. On older libcurl they are written once to a private temporary file
/// and that path is reused, which is still better than a path that can vanish.
///
/// Has no effect on Darwin, where URLSession uses the system trust store.
public enum PicaroonCertificateAuthority {

    private static let lock = NSLock()
    private static var storedPEM: Data?
    private static var storedFallbackPath: String?
    private static var storedInsecure = false
    private static var storedDirectory: String?

    /// Use these PEM bytes as the CA bundle for every subsequent request.
    /// Use these PEM bytes, and when a file has to be written (libcurl older than
    /// 7.77, which lacks CURLOPT_CAINFO_BLOB) put it in `directory`.
    ///
    /// Supply a directory the OS will not empty underneath you. On Android that
    /// means `context.filesDir`, NOT `context.cacheDir` -- and note that
    /// NSTemporaryDirectory() resolves to the cache directory there, which is why
    /// it is not a safe default.
    public static func use(pem: Data, directory: String) {
        lock.lock()
        storedDirectory = directory
        lock.unlock()
        use(pem: pem)
    }

    public static func use(pem: Data) {
        lock.lock()
        storedPEM = pem
        storedInsecure = false
        // Any file written for a previous bundle is stale now.
        if let path = storedFallbackPath {
            try? FileManager.default.removeItem(atPath: path)
            storedFallbackPath = nil
        }
        lock.unlock()
    }

    /// Revert to the platform default: the `URLSessionCertificateAuthorityInfoFile`
    /// environment variable if set, otherwise whatever libcurl was built with.
    public static func useSystemDefault() {
        lock.lock()
        storedPEM = nil
        storedInsecure = false
        if let path = storedFallbackPath {
            try? FileManager.default.removeItem(atPath: path)
            storedFallbackPath = nil
        }
        lock.unlock()
    }

    /// Disable peer and host verification. Debugging and test servers only -- this
    /// makes the connection trivially interceptable.
    public static func disableVerificationForTesting() {
        lock.lock()
        storedPEM = nil
        storedInsecure = true
        lock.unlock()
    }

    // MARK: - Internal

    /// Read once at first use. `getenv` hands back a pointer into the environment
    /// block, which a concurrent `setenv` from any thread may free and reallocate,
    /// so calling it per request from every worker is a use-after-free waiting to
    /// happen. One read at startup sidesteps that entirely.
    internal static let environmentPath: String? = {
        guard let value = getenv("URLSessionCertificateAuthorityInfoFile") else { return nil }
        let path = String(cString: value)
        return path.isEmpty ? nil : path
    }()

    internal static let environmentRequestsInsecure: Bool = {
        return environmentPath == "INSECURE_SSL_NO_VERIFY"
    }()

    /// Forget any file we wrote, so the next request rewrites it. Called when
    /// libcurl reports the CA file unreadable, which is how a cleared cache
    /// directory manifests.
    internal static func invalidateFallbackFile() {
        lock.lock()
        if let path = storedFallbackPath {
            try? FileManager.default.removeItem(atPath: path)
            storedFallbackPath = nil
        }
        lock.unlock()
    }

    /// Set PICAROON_FORCE_CAINFO_FILE=1 to exercise the file fallback even where
    /// CURLOPT_CAINFO_BLOB is available.
    internal static let forceFallbackFile: Bool = {
        let value = ProcessInfo.processInfo.environment["PICAROON_FORCE_CAINFO_FILE"]
        return value != nil && value != "0"
    }()

    internal static var pem: Data? {
        lock.lock(); defer { lock.unlock() }
        return storedPEM
    }

    internal static var isInsecure: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedInsecure || environmentRequestsInsecure
    }

    /// Path to a file holding the supplied PEM, written on first use. Only needed
    /// when the runtime libcurl predates CURLOPT_CAINFO_BLOB.
    internal static func fallbackFilePath() -> String? {
        lock.lock(); defer { lock.unlock() }

        if let path = storedFallbackPath,
           FileManager.default.fileExists(atPath: path) {
            return path
        }
        guard let pem = storedPEM else { return nil }

        // Default to NSTemporaryDirectory(), but be aware that on Android it resolves
        // to the app's CACHE directory, which the OS may empty at any moment without
        // notifying the process. That produces an intermittent
        //   "error setting certificate file: .../cache/cacert.pem"  (CURLE_SSL_CACERT_BADFILE)
        // in the middle of otherwise healthy traffic. Pass a directory to
        // use(pem:directory:) -- context.filesDir on Android -- to avoid it.
        let directory = storedDirectory ?? NSTemporaryDirectory()
        let separator = directory.hasSuffix("/") ? "" : "/"
        let path = directory + separator + "picaroon-cacert.pem"
        do {
            try pem.write(to: URL(fileURLWithPath: path), options: .atomic)
            storedFallbackPath = path
            return path
        } catch {
            return nil
        }
    }
}
