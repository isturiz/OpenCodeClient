import Foundation
import Testing

@testable import OpenCodeClient

struct ServerURLPolicyTests {
    @Test func acceptsSecureAndLocalAddresses() throws {
        let secure = try ServerURLPolicy.normalizedURL(from: " https://mac.example.ts.net/ ")
        let privateIPv4 = try ServerURLPolicy.normalizedURL(from: "http://192.168.1.8:4096/")
        let localDNS = try ServerURLPolicy.normalizedURL(from: "http://studio.local:4096")

        #expect(secure.absoluteString == "https://mac.example.ts.net/")
        #expect(privateIPv4.absoluteString == "http://192.168.1.8:4096/")
        #expect(localDNS.host() == "studio.local")
    }

    @Test func rejectsPublicPlainHTTP() {
        #expect(throws: NetworkError.insecureRemoteURL) {
            try ServerURLPolicy.normalizedURL(from: "http://example.com:4096")
        }
    }

    @Test func rejectsQueryAndFragmentInBaseURL() {
        #expect(throws: NetworkError.invalidURL) {
            try ServerURLPolicy.normalizedURL(from: "https://example.com?token=secret")
        }
        #expect(throws: NetworkError.invalidURL) {
            try ServerURLPolicy.normalizedURL(from: "https://example.com/#fragment")
        }
    }

    @Test func preservesReverseProxyPathAndEncodesDirectory() throws {
        let baseURL = try ServerURLPolicy.normalizedURL(from: "https://example.com/opencode/")
        let result = try ServerURLPolicy.appending(
            path: "/session",
            to: baseURL,
            queryItems: [URLQueryItem(name: "directory", value: "/tmp/My Project")]
        )
        let query = try #require(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(result.path() == "/opencode/session")
        #expect(query == [URLQueryItem(name: "directory", value: "/tmp/My Project")])
    }
}
