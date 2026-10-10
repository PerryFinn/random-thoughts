import Foundation

nonisolated struct MarkdownDiff {
    enum Kind { case context, deletion, insertion }
    struct Line: Identifiable {
        let id: Int
        let kind: Kind
        let text: String
        let hasNewline: Bool
        let oldNumber: Int?
        let newNumber: Int?
    }
    private struct SourceLine {
        let text: String
        let hasNewline: Bool
    }

    let lines: [Line]
    let unifiedText: String

    init(previous: String, proposed: String) {
        guard !previous.utf8.elementsEqual(proposed.utf8) else {
            lines = []
            unifiedText = "正文无变化"
            return
        }
        let old = Self.split(previous)
        let new = Self.split(proposed)
        let changes = new.difference(from: old) {
            $0.text.utf8.elementsEqual($1.text.utf8) && $0.hasNewline == $1.hasNewline
        }
        var removals: Set<Int> = []
        var insertions: Set<Int> = []
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removals.insert(offset)
            case .insert(let offset, _, _): insertions.insert(offset)
            }
        }
        var result: [Line] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            let source: SourceLine
            let kind: Kind
            let oldNumber: Int?
            let newNumber: Int?
            if removals.contains(oldIndex) {
                source = old[oldIndex]
                kind = .deletion
                oldNumber = oldIndex + 1
                newNumber = nil
                oldIndex += 1
            } else if insertions.contains(newIndex) {
                source = new[newIndex]
                kind = .insertion
                oldNumber = nil
                newNumber = newIndex + 1
                newIndex += 1
            } else {
                source = old[oldIndex]
                kind = .context
                oldNumber = oldIndex + 1
                newNumber = newIndex + 1
                oldIndex += 1
                newIndex += 1
            }
            result.append(Line(id: result.count, kind: kind, text: source.text, hasNewline: source.hasNewline, oldNumber: oldNumber, newNumber: newNumber))
        }
        lines = result
        var text = "--- 已保存正文\n+++ 待保存正文\n@@ -\(old.isEmpty ? 0 : 1),\(old.count) +\(new.isEmpty ? 0 : 1),\(new.count) @@\n"
        for line in result {
            let prefix = line.kind == .deletion ? "-" : line.kind == .insertion ? "+" : " "
            text += prefix + line.text + "\n"
            if !line.hasNewline { text += "\\ No newline at end of file\n" }
        }
        unifiedText = text
    }

    private static func split(_ text: String) -> [SourceLine] {
        guard !text.isEmpty else { return [] }
        var parts = text.components(separatedBy: "\n")
        let finalNewline = parts.last == ""
        if finalNewline { parts.removeLast() }
        return parts.enumerated().map { SourceLine(text: $0.element, hasNewline: $0.offset < parts.count - 1 || finalNewline) }
    }
}
