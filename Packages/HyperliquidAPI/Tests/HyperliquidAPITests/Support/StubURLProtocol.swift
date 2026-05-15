// SPDX-License-Identifier: MIT

import Foundation

/// A `URLProtocol` subclass that intercepts every request and returns a
/// handler-supplied response without touching the network.
///
/// Usage in tests:
/// ```swift
/// StubURLProtocol.handler = { request in
///     let response = HTTPURLResponse(
///         url: request.url!,
///         statusCode: 200,
///         httpVersion: nil,
///         headerFields: nil
///     )!
///     return .success((response, fixtureData))
/// }
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [StubURLProtocol.self]
/// let session = URLSession(configuration: config)
/// // Hand session to URLSessionHyperliquidClient's test-seam init.
/// ```
///
/// `handler` is a `nonisolated(unsafe)` static because `URLProtocol`'s
/// `startLoading` is called by the URL loading system on an arbitrary thread
/// and cannot be `async`. Tests set the handler before creating the session
/// and clear it in teardown. Swift 6 strict isolation is satisfied by the
/// deliberate `nonisolated(unsafe)` annotation, which is appropriate here
/// because the URL loading system serializes calls per-request and tests
/// ensure the handler is set before any request is made.
final class StubURLProtocol: URLProtocol {

    /// The result the stub returns. Set this before issuing a request.
    /// - `.success((response, data?))` — delivers the response then data then finishes.
    /// - `.failure(error)` — fails with the error.
    nonisolated(unsafe) static var handler: ((URLRequest) -> Result<(HTTPURLResponse, Data?), Error>)?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: StubError.noHandlerInstalled)
            return
        }

        switch handler(request) {
        case .success(let (response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    enum StubError: Error {
        case noHandlerInstalled
    }
}

// MARK: - Convenience builder

extension StubURLProtocol {

    /// Returns a pre-configured ephemeral `URLSession` with this protocol
    /// registered. Pass the session to `URLSessionHyperliquidClient`'s
    /// test-seam initializer.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        // Disable waiting for connectivity so tests fail immediately rather
        // than hanging for 30 seconds when the stub rejects a request.
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    /// Extracts the HTTP body bytes from a `URLRequest` as seen inside a
    /// `URLProtocol` subclass.
    ///
    /// URLSession converts `httpBody` to `httpBodyStream` before handing the
    /// request to a registered `URLProtocol`, so `request.httpBody` is always
    /// `nil` at that point. This helper drains whichever source is populated.
    static func bodyData(for request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
