import Foundation
import Testing
@testable import random_thoughts

struct MarkdownPresentationTests {
    @Test func previewRetainsParagraphAndListBoundariesAlongsideInlineFormatting() {
        let rendered = SafeMarkdown.render("# 标题\n\n段落一\n\n段落二 **粗体**\n\n- 项目一\n- 项目二\n\n1. 序号项\n")
        let text = String(rendered.characters)
        #expect(text.contains("标题\n\n段落一\n\n段落二 粗体"))
        #expect(text.contains("• 项目一\n• 项目二"))
        #expect(text.contains("1. 序号项"))
        #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test func unifiedDiffPreservesWhitespaceUnicodeAndMissingFinalNewline() {
        let diff = MarkdownDiff(previous: "标题\n相同\n删除  \n", proposed: "标题\n相同\n新增 👩🏽‍💻")
        #expect(diff.unifiedText == "--- 已保存正文\n+++ 待保存正文\n@@ -1,3 +1,3 @@\n 标题\n 相同\n-删除  \n+新增 👩🏽‍💻\n\\ No newline at end of file\n")
        #expect(MarkdownDiff(previous: "é", proposed: "e\u{301}").lines.contains { $0.kind == .insertion })
        #expect(MarkdownDiff(previous: "same\n", proposed: "same\n").lines.isEmpty)
    }

    @Test func previewKeepsOnlyLinksThatCanBeExplicitlyOpened() {
        let rendered = SafeMarkdown.render("""
            # 合成预览
            <script>synthetic()</script>
            ![远程图片](https://example.invalid/image.png)
            [安全链接](https://example.invalid/page)
            [危险链接](javascript:synthetic())
            [本地文件](file:///synthetic-private)
            """)
        let links = rendered.runs.compactMap(\.link)
        #expect(links.contains(URL(string: "https://example.invalid/page")!))
        #expect(links.allSatisfy { ["http", "https", "mailto"].contains($0.scheme?.lowercased() ?? "") })
    }
}
