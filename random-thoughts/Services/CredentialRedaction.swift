import Foundation

nonisolated enum CredentialRedaction {
    static func redact(_ text: String) throws -> String {
        let patterns: [(String, String)] = [
            (#"(?s)-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"#, "[已遮盖私钥]"),
            (#"(?i)(\b(?:authorization|proxy-authorization)\s*[:=]\s*(?:bearer|basic)\s+)[A-Za-z0-9+/=._-]{8,}"#, "$1[已遮盖凭据]"),
            (#"(?i)(\b(?:api[_-]?key|access[_-]?token|secret[_-]?key|password)\s*[:=]\s*[\"']?)[^\s\"']{8,}"#, "$1[已遮盖凭据]"),
            (#"\b(?:sk-(?:proj-|ant-api[0-9]{2}-)?|ghp_|github_pat_|glpat-|xox[baprs]-)[A-Za-z0-9_-]{16,}"#, "[已遮盖凭据]")
        ]
        // Compile before modifying the copy, so a rule error cannot discard already completed replacements.
        let rules = try patterns.map { (try NSRegularExpression(pattern: $0.0), $0.1) }
        return rules.reduce(text) { value, rule in
            rule.0.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: rule.1)
        }
    }
}
