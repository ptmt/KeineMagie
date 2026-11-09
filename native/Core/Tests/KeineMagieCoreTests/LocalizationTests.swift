import Foundation
import Testing
@testable import KeineMagieCore

@Test func packageLoadsRealTranslationsAndFormatsStatusCodes() throws {
    let expected = ["de": "Deutsch", "en": "German", "ru": "Немецкий", "es": "Alemán", "fr": "Allemand"]
    for (language, title) in expected {
        let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        #expect(bundle.localizedString(forKey: "language.german", value: nil, table: nil) == title)
        let format = bundle.localizedString(forKey: "login.http", value: nil, table: nil)
        let message = String(format: format, locale: Locale(identifier: language), 503)
        #expect(message.contains("503"))
        #expect(!message.contains("%d"))
        #expect(message != "login.http")
    }
    #expect(APIError.emptyText.localizedDescription != "api.empty")
    #expect(AuthError.invalidCredential.localizedDescription != "auth.invalid")
    #expect(APIError.http(503).localizedDescription.contains("503"))
}
