import Foundation
import XCTest
@testable import Catoshi

final class UpdateCheckTests: XCTestCase {
    func testVersionOrderingUsesNumbersAndPrereleasePrecedence() throws {
        let versions = ["v2.16.9", "2.16.12-beta.2", "2.16.12-beta.10", "2.16.12", "2.17.0", "3.0.0"]
        let parsed = try versions.map { try XCTUnwrap(CatoshiVersion($0)) }
        XCTAssertEqual(parsed.sorted(), parsed)
        for pair in zip(parsed, parsed.dropFirst()) { XCTAssertLessThan(pair.0, pair.1) }
        XCTAssertEqual(CatoshiVersion("v2.16.12"), CatoshiVersion("2.16.12"))
        for invalid in ["", "v", "2.16", "2.16.12.1", "2.16.-1", "2.016.12", "2.16.12-", "2.16.12-beta.01", "https://example.com", "2.16.12/other"] {
            XCTAssertNil(CatoshiVersion(invalid), invalid)
        }
    }

    func testSelectionIncludesPublicBetaAndIgnoresDraftsAndInvalidTags() throws {
        let releases = [release("v2.16.9"), release("v2.16.13", beta: true), release("v9.0.0", draft: true), release("malformed")]
        let latest = try XCTUnwrap(UpdateCheckService.newest(in: releases))
        XCTAssertEqual(latest.tagName, "v2.16.13")
        XCTAssertEqual(latest.url.absoluteString, "https://github.com/Rayeonjin/Catoshi/releases/tag/v2.16.13")
        XCTAssertTrue(UpdateCheckResult(current: try XCTUnwrap(CatoshiVersion("2.16.12")), latest: latest).hasUpdate)
        XCTAssertFalse(UpdateCheckResult(current: try XCTUnwrap(CatoshiVersion("2.16.13")), latest: latest).hasUpdate)
        XCTAssertTrue(UpdateCheckResult(current: try XCTUnwrap(CatoshiVersion("2.16.14")), latest: latest).isAhead)
        XCTAssertNil(UpdateCheckService.newest(in: [release("invalid"), release("v9.0.0", draft: true)]))
    }

    func testCheckUsesFixedPublicEndpointAndFindsNewerVersionOnNextPage() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        UpdateProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.url?.path, "/repos/Rayeonjin/Catoshi/releases")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            if URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value == "1" {
                let entry = "{\"tag_name\":\"v2.16.9\",\"draft\":false,\"prerelease\":true}"
                return (200, Data(("[" + Array(repeating: entry, count: 100).joined(separator: ",") + "]").utf8))
            }
            return (200, Data("[{\"tag_name\":\"v2.16.13\",\"draft\":false,\"prerelease\":true,\"html_url\":\"https://untrusted.example\"}]".utf8))
        }
        let result = try await UpdateCheckService(session: session).check(currentVersion: "2.16.12")
        XCTAssertTrue(result.hasUpdate)
        XCTAssertEqual(result.latest.tagName, "v2.16.13")
        XCTAssertEqual(result.latest.url.host, "github.com")
    }

    func testFailureNeverProducesAnUpToDateResult() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for (status, body) in [(429, "[]"), (500, "[]"), (200, "[]"), (200, "invalid JSON")] {
            UpdateProtocol.handler = { _ in (status, Data(body.utf8)) }
            do {
                _ = try await UpdateCheckService(session: session).check(currentVersion: "2.16.12")
                XCTFail("Expected failure for \(status), \(body)")
            } catch {
                if status == 429 { XCTAssertTrue(error is UpdateCheckError) }
            }
        }
    }

    private func release(_ tag: String, beta: Bool = false, draft: Bool = false) -> CatoshiRelease {
        CatoshiRelease(tagName: tag, draft: draft, prerelease: beta)
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class UpdateProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
