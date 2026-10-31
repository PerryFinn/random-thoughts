import Foundation
import Testing
@testable import random_thoughts

struct ReportPayloadTests {
    @Test(arguments: [
        "- complete\n\n---\n\n- more", "\\-", "`-`", "- pending review", "```markdown\n## literal\n```", "before\n\n    ## code literal\n\nafter",
        "```markdown\n#\n##\n```", "[r]: #\n---", "[r]:\n/path\n\n---", "[r]:\n<#>\n\n---"
    ])
    func validHorizontalRulesAndCodeDoNotBecomeForbiddenHeadings(_ body: String) throws {
        var sections = Dictionary(uniqueKeysWithValues: ReportPayload.keys.map { ($0, "") })
        sections["overview"] = body
        let payload = String(decoding: try JSONEncoder().encode(sections), as: UTF8.self)
        #expect(try ReportPayload.render(payload, language: .english).contains(body))
    }
    @Test func credentialMaskingAppliesOnlyToBodiesAndCannotRewriteTheFixedTemplate() async throws {
        let value = #"{"overview":"今日概览 是合成凭据","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"#
        let accepted = try await ReportPayload.maskAndRender(value, language: .chinese, credential: "今日概览", redact: { $0 })
        #expect(accepted.markdown.hasPrefix("## 今日概览\n\n[已遮盖凭据] 是合成凭据"))
        #expect(accepted.markdown.components(separatedBy: "## ").count == 7)
    }
    @Test func emptySectionsHaveFixedLocalizedTitlesAndPlaceholders() throws {
        let payload = #"{"overview":"","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"#
        let english = try ReportPayload.render(payload, language: .english)
        #expect(english.contains("## Today’s Overview\n\nNo confirmed content"))
        #expect(english.components(separatedBy: "No confirmed content").count == 7)
        let chinese = try ReportPayload.render(payload, language: .chinese)
        #expect(chinese.contains("## 明日计划\n\n无明确内容"))
    }
    @Test(arguments: [
        #"{"overview":"","completed":"","deliverables":"","decisions":"","risks":""}"#,
        #"{"overview":"","overview":"duplicate","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"#,
        #"{"overview":"","completed":"","deliverables":"","decisions":"","risks":"","plans":"","other":""}"#,
        ###"{"overview":"## forged heading","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"###,
        ##"{"overview":"#","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"##,
        ###"{"overview":"##","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"###,
        ###"{"overview":"## ** **","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"###,
        ###"{"overview":"> ##","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"###,
        ###"{"overview":"1. ##","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"###,
        ###"{"overview":"> - ##","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"###,
        ##"{"overview":"[r]:\n#\n---","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"##,
        ###"{"overview":"[multi\nline]:\n##\n---","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"###,
        ##"{"overview":"> [r]:\n> #\n> ---","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"##,
        ##"{"overview":"- [r]:\n  #\n  ---","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"##,
        ###"{"overview":"[r]:\n#\n##","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"###,
        ##"{"overview":"[]:\n#","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"##,
        ##"{"overview":"[r]:\n\n#","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"##,
        ##"{"overview":"[r]: /ok\n\n#","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"##,
        ##"{"overview":"[r]: /ok\n#","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"##,
        #"{"overview":"Heading\n===","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"#,
        #"{"overview":"```text\nunclosed","completed":"","deliverables":"","decisions":"","risks":"","plans":""}"#,
        #"{"overview":"","completed":"","deliverables":"","decisions":"","risks":"","plans":""} extra"#
    ])
    func malformedSixSectionPayloadCannotBecomeADraft(_ payload: String) {
        #expect(throws: AIRequestError.invalidResponse) { try ReportPayload.render(payload, language: .chinese) }
    }
}
