import Testing
import Foundation
@testable import EasyDemo

struct OpenAITransportTests {
    @Test func unauthorizedRequestProducesActionableError() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UnauthorizedProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let editor = OpenAIEditor(session: session)
        do {
            _ = try await editor.request(path: "responses", key: "fixture-key", contentType: "application/json", body: Data("{}".utf8))
            Issue.record("Expected an authorization error")
        } catch {
            #expect(error.localizedDescription.contains("API key was rejected"))
            #expect(!error.localizedDescription.contains("fixture-key"))
        }
    }

    @Test func cancellingAnInFlightRequestCompletesWithoutEditingSources() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WaitingProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let editor = OpenAIEditor(session: session)
        let request = Task {
            try await editor.request(path: "responses", key: "fixture-key", contentType: "application/json", body: Data("{}".utf8))
        }
        try await Task.sleep(for: .milliseconds(50))
        request.cancel()
        do { _ = try await request.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError || (error as? URLError)?.code == .cancelled) }
    }
}

private class UnauthorizedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class WaitingProtocol: UnauthorizedProtocol {
    override func startLoading() {}
}
