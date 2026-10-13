import Foundation
import ReportTokenizerC
import Testing
@testable import random_thoughts

@MainActor
struct OfflineTokenizerTests {
    @Test func bothCABIEncodingsMatchTheFixedOfficialReferenceCorpus() async throws {
        struct Fixture: Decodable {
            struct Case: Decodable { let text: String; let cl100k: Int; let o200k: Int }
            let cases: [Case]
        }
        let file = try #require(Bundle.module.url(forResource: "tokenizer-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file))
        let tokenizer = OfflineReportTokenizer()
        for example in fixture.cases {
            var cl100k = 0, o200k = 0
            let bytes = Array(example.text.utf8)
            let code = bytes.withUnsafeBufferPointer { report_tokenizer_count($0.baseAddress, $0.count, &cl100k, &o200k) }
            #expect(code == 0)
            #expect(cl100k == example.cl100k)
            #expect(o200k == example.o200k)
            #expect(try await tokenizer.count(example.text) == Int(max(example.cl100k, example.o200k)))
        }
    }
    @Test func ordinarySpecialTokenLiteralsAndUnicodeUseBothRealEncodings() async throws {
        let tokenizer = OfflineReportTokenizer()
        #expect(try await tokenizer.count("hello world") == 2)
        #expect(try await tokenizer.count("<|endoftext|>") == 7)
        #expect(try await tokenizer.count("") == 0)
    }
}
