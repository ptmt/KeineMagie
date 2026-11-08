import Testing
@testable import KeineMagieCore

@Test func endpointValidatesTransportAndPreservesRoutePrefix() throws {
    #expect(try ServerEndpoint("https://example.com/keine-magie/").url(path: "v1/translations").absoluteString == "https://example.com/keine-magie/v1/translations")
    #expect(try ServerEndpoint("http://localhost:8787", allowLocalHTTP: true).url(path: "tts").absoluteString == "http://localhost:8787/tts")
    for invalid in ["", "file:///tmp/a", "ftp://example.com", "https://user:pass@example.com", "https://example.com?token=x", "https://example.com/#x", "http://example.com", "example.com"] {
        #expect(throws: (any Error).self) { try ServerEndpoint(invalid, allowLocalHTTP: true) }
    }
    #expect(throws: (any Error).self) { try ServerEndpoint("http://localhost:8787") }
    #expect(throws: (any Error).self) { try ServerEndpoint("http://192.168.1.3:8787", allowLocalHTTP: true) }
}
