import Foundation
import Testing
@testable import random_thoughts

struct ReportCompactFactTests {
    @Test(arguments: [
        #"{"covered":[1],"noRelevantContent":true,"facts":[]}"#,
        #"{"covered":[1],"noRelevantContent":true,"groups":[],"extra":0}"#,
        #"{"covered":[1],"covered":[1],"noRelevantContent":true,"groups":[]}"#,
        #"{"covered":[1],"noRelevantContent":true}"#,
        #"{"covered":[1],"groups":[]}"#,
        #"{"noRelevantContent":true,"groups":[]}"#,
        #"{"covered":[1],"noRelevantContent":0,"groups":[]}"#,
        #"{"covered":[true],"noRelevantContent":true,"groups":[]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":{}}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","facts":[]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"status":"uncertain","facts":[{"turns":["1/1"],"summary":"fact"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"facts":[{"turns":["1/1"],"summary":"fact"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain"}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","extra":0,"facts":[{"turns":["1/1"],"summary":"fact"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"unknown","facts":[{"turns":["1/1"],"summary":"fact"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[true],"status":"uncertain","facts":[{"turns":["1/1"],"summary":"fact"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","status":"confirmed","facts":[{"turns":["1/1"],"summary":"fact"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","facts":[{"summary":"fact"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","facts":[{"turns":["1/1"]}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","facts":[{"turns":["1/1"],"summary":null}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","facts":[{"turns":[1],"summary":"fact"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","facts":[{"turns":["1/1"],"summary":"fact","status":"confirmed"}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","facts":[{"turns":["1/1"],"summary":"fact","references":[1]}]}]}"#,
        #"{"covered":[1],"noRelevantContent":false,"groups":[{"references":[1],"status":"uncertain","facts":[{"turns":["1/1"],"summary":"fact","\u0073ummary":"other"}]}]}"#
    ])
    func groupedResponsesRejectOldShapesAndMalformedOrAmbiguousFields(_ text: String) {
        #expect(throws: AIRequestError.invalidResponse) { try ReportFactPayload.parse(text) }
    }

    @Test func groupedResponsesRestoreEveryFieldWithoutReorderingOrChangingSummaryBytes() throws {
        let text = #"{"covered":[25,26],"noRelevantContent":false,"groups":[{"references":[25,26],"status":"uncertain","facts":[{"turns":["1/1","2/1"],"summary":"原因甲只影响 A；原因乙范围未指定。\n\"引号\" \\ e\u0301 👩🏽‍💻 </script>"},{"turns":["2/1"],"summary":"第二条仍未确定。"}]},{"references":[26,25],"status":"uncertain","facts":[{"turns":["2/1","1/1"],"summary":"引用顺序不同，不合并。"}]},{"references":[25],"status":"confirmed","facts":[{"turns":["1/1"],"summary":"文档完成。"}]},{"references":[25],"status":"unconfirmed","facts":[{"turns":["1/1"],"summary":"发布仍未确认。"}]},{"references":[25,26],"status":"uncertain","facts":[{"turns":["1/1"],"summary":"不能跨组重排。"}]}]}"#
        let payload = try ReportFactPayload.parse(text)
        #expect(payload.covered == [25, 26] && !payload.noRelevantContent)
        #expect(payload.facts.map(\.references) == [[25, 26], [25, 26], [26, 25], [25], [25], [25, 26]])
        #expect(payload.facts.map(\.turns) == [["1/1", "2/1"], ["2/1"], ["2/1", "1/1"], ["1/1"], ["1/1"], ["1/1"]])
        #expect(payload.facts.map(\.status) == [.uncertain, .uncertain, .uncertain, .confirmed, .unconfirmed, .uncertain])
        let summaries = ["原因甲只影响 A；原因乙范围未指定。\n\"引号\" \\ e\u{301} 👩🏽‍💻 </script>",
                         "第二条仍未确定。", "引用顺序不同，不合并。", "文档完成。", "发布仍未确认。", "不能跨组重排。"]
        for (fact, summary) in zip(payload.facts, summaries) {
            #expect(fact.summary.utf8.elementsEqual(summary.utf8))
        }
        let canonical = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(text.utf8)),
                                                    options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(try ReportJSON.encode(payload).utf8.elementsEqual(canonical))
    }
}
