import Foundation
import Flynn

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

internal final class HTTPTransportSession {

    internal let configuration: URLSessionConfiguration

    #if os(Linux) || os(Android)
    // Deliberately no URLSession. Requests here go through CurlTransport, which
    // takes its timeout and cookie storage from `configuration` directly.
    #else
    internal let urlSession: URLSession
    #endif

    internal init(configuration: URLSessionConfiguration) {
        self.configuration = configuration

        #if os(Linux) || os(Android)
        #else
        urlSession = URLSession(configuration: configuration,
                                delegate: nil,
                                delegateQueue: nil)
        #endif
    }

    /// Mirrors URLSession.invalidateAndCancel() where there is a URLSession to
    /// invalidate.
    ///
    /// On Linux and Android there is nothing to invalidate here, and that is a
    /// real gap rather than a no-op worth ignoring: in-flight work on those
    /// platforms belongs to CurlTransport, and cancelling it needs per-task
    /// cancellation through HTTPTaskManager, which does not track tasks by
    /// session yet. See the note on HTTPSession._beCancel().
    internal func invalidateAndCancel() {
        #if os(Linux) || os(Android)
        #else
        urlSession.invalidateAndCancel()
        #endif
    }
}
