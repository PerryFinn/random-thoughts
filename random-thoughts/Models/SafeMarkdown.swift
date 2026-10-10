import Foundation

nonisolated enum SafeMarkdown {
    static func render(_ markdown: String) -> AttributedString {
        let parsed = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)))
            ?? AttributedString(markdown)
        var rendered = AttributedString()
        var previous: PresentationIntent?
        for run in parsed.runs {
            let intent = run.presentationIntent
            let item = intent?.components.first { if case .listItem = $0.kind { true } else { false } }
            let previousItem = previous?.components.first { if case .listItem = $0.kind { true } else { false } }
            let list = intent?.components.first { [.orderedList, .unorderedList].contains($0.kind) }
            if intent != previous, !rendered.characters.isEmpty {
                let sharesList = list.map { previous?.components.contains($0) == true } ?? false
                rendered.append(AttributedString(sharesList && item?.identity != previousItem?.identity ? "\n" : "\n\n"))
            }
            if let item, item.identity != previousItem?.identity, case .listItem(let ordinal) = item.kind {
                let depth = intent?.components.filter { [.orderedList, .unorderedList].contains($0.kind) }.count ?? 1
                let marker = list?.kind == .orderedList ? "\(ordinal). " : "• "
                rendered.append(AttributedString(String(repeating: "  ", count: max(0, depth - 1)) + marker))
            }
            rendered.append(AttributedString(parsed[run.range]))
            previous = intent
        }
        let unsafeRanges = rendered.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let link = run.link, !["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") else { return nil }
            return run.range
        }
        for range in unsafeRanges { rendered[range].link = nil }
        return rendered
    }
}
