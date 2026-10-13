import Foundation
#if SWIFT_PACKAGE
import ReportTokenizerC
#endif

protocol ReportTokenCounting: Sendable {
    nonisolated func count(_ text: String) async throws -> Int
}

actor OfflineReportTokenizer: ReportTokenCounting {
    func count(_ text: String) async throws -> Int {
        try Task.checkCancellation()
        let bytes = Array(text.utf8)
        var cl100k = 0, o200k = 0
        let status = bytes.withUnsafeBufferPointer {
            report_tokenizer_count($0.baseAddress, $0.count, &cl100k, &o200k)
        }
        guard status == 0, cl100k >= 0, o200k >= 0 else { throw AIRequestError.tokenizer }
        try Task.checkCancellation()
        return max(cl100k, o200k)
    }
}
