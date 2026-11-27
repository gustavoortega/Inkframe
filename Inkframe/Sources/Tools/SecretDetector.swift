import Foundation

/// Flags OCR lines that look like credentials or account identifiers.
/// The patterns are lax on purpose: a hit redacts the whole observation, and Cmd+Z undoes a false positive.
enum SecretDetector {
    private static let patterns: [NSRegularExpression] = [
        // AWS key ids; `[I1l]` covers OCR confusing the second letter.
        #"\b(AK[I1l]A|ASIA|AROA|AIDA|AGPA|ANPA|ANVA|AIPA)[A-Z0-9]{8,}"#,
        #"eyJ[A-Za-z0-9_-]{5,}"#,
        #"gh[pousr]_[A-Za-z0-9]{10,}"#,
        #"github_pat_"#,
        #"xox[abprse]-"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY"#,
        #"arn:aws[a-z-]*:"#,
        #"(?<!\d)\d{12}(?!\d)"#,
        // The AWS console header shows the account id hyphenated.
        #"(?<!\d)\d{4}-\d{4}-\d{4}(?!\d)"#,
        #"(?<![\d.])\d{1,3}(\.\d{1,3}){3}(?![\d.])"#,
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        #"(?i)(password|passwd|secret|token|api[_-]?key|authorization)\s*[:=]"#,
        // Wrapped continuation of base64 secrets. `-` is excluded so UUIDs and resource names survive.
        #"(?=[A-Za-z0-9+/=_]*[A-Za-z])(?=[A-Za-z0-9+/=_]*\d)[A-Za-z0-9+/=_]{24,}"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    static func isSensitive(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return patterns.contains { $0.firstMatch(in: line, range: range) != nil }
    }
}
