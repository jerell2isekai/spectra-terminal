#if ENABLE_SIDECAR
import Foundation

/// 4-stage sanitization pipeline for terminal content before sending to external LLMs.
///
/// Stage 1: Control sequence removal (CSI, OSC, DCS, C0/C1 except \n \t)
/// Stage 2: Display normalization (zero-width chars, bidi overrides, normalize newlines)
/// Stage 3: Secret redaction (API keys, tokens, private keys)
/// Stage 4: Size guard (truncate to maxLength)
enum TerminalContentSanitizer {

    /// Run the full 4-stage pipeline.
    static func sanitize(_ text: String, maxLength: Int = 50_000) -> String {
        var result = text
        result = stripControlSequences(result)
        result = normalizeDisplay(result)
        result = redactSecrets(result)
        result = truncate(result, maxLength: maxLength)
        return result
    }

    // MARK: - Stage 1: Control Sequence Removal

    /// Remove ANSI CSI, OSC, DCS, and other escape sequences.
    /// Preserves \n and \t. Strips all other C0 controls.
    static func stripControlSequences(_ text: String) -> String {
        var result = text

        // CSI sequences: ESC [ ... final_byte
        result = result.replacingOccurrences(
            of: "\\x1b\\[[0-?]*[ -/]*[@-~]",
            with: "", options: .regularExpression
        )

        // OSC sequences: ESC ] ... (ST or BEL)
        // ST = ESC \ or 0x9C; BEL = 0x07
        result = result.replacingOccurrences(
            of: "\\x1b\\].*?(?:\\x1b\\\\|\\x07)",
            with: "", options: .regularExpression
        )

        // DCS sequences: ESC P ... ST
        result = result.replacingOccurrences(
            of: "\\x1bP.*?\\x1b\\\\",
            with: "", options: .regularExpression
        )

        // Remaining lone ESC + single char (SS2, SS3, etc.)
        result = result.replacingOccurrences(
            of: "\\x1b[NO@-~]",
            with: "", options: .regularExpression
        )

        // Strip C0 control chars except \n (0x0A) and \t (0x09)
        result = result.unicodeScalars.filter { scalar in
            if scalar.value == 0x0A || scalar.value == 0x09 { return true }
            if scalar.value < 0x20 { return false } // C0
            if scalar.value == 0x7F { return false } // DEL
            if scalar.value >= 0x80 && scalar.value <= 0x9F { return false } // C1
            return true
        }.map { String($0) }.joined()

        return result
    }

    // MARK: - Stage 2: Display Normalization

    /// Remove zero-width characters and bidi overrides that could enable visual spoofing.
    static func normalizeDisplay(_ text: String) -> String {
        var result = text

        // Zero-width chars
        let zeroWidth: [Character] = [
            "\u{200B}", // ZWSP
            "\u{200C}", // ZWNJ
            "\u{200D}", // ZWJ
            "\u{FEFF}", // BOM / ZWNBSP
        ]
        result = String(result.filter { !zeroWidth.contains($0) })

        // Bidi override/embedding chars (U+202A-U+202E, U+2066-U+2069)
        result = result.unicodeScalars.filter { scalar in
            if scalar.value >= 0x202A && scalar.value <= 0x202E { return false }
            if scalar.value >= 0x2066 && scalar.value <= 0x2069 { return false }
            return true
        }.map { String($0) }.joined()

        // Normalize line endings
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        return result
    }

    // MARK: - Stage 3: Secret Redaction

    /// Redact common credential patterns before sending to external LLMs.
    static func redactSecrets(_ text: String) -> String {
        var result = text

        let patterns: [(String, String)] = [
            // Anthropic API keys
            ("sk-ant-[a-zA-Z0-9_-]{20,}", "[REDACTED:anthropic-key]"),
            // OpenAI API keys
            ("sk-[a-zA-Z0-9]{20,}", "[REDACTED:openai-key]"),
            // GitHub tokens
            ("ghp_[a-zA-Z0-9]{36}", "[REDACTED:github-pat]"),
            ("gho_[a-zA-Z0-9]{36}", "[REDACTED:github-oauth]"),
            ("ghs_[a-zA-Z0-9]{36}", "[REDACTED:github-app]"),
            // Bearer tokens
            ("Bearer\\s+[a-zA-Z0-9._\\-]{20,}", "[REDACTED:bearer-token]"),
            // AWS keys
            ("AKIA[0-9A-Z]{16}", "[REDACTED:aws-key]"),
            // Private keys
            ("-----BEGIN[A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END[A-Z ]*PRIVATE KEY-----",
             "[REDACTED:private-key]"),
            // Generic: high-entropy strings in KEY=value or export KEY= context
            ("(?:(?:API_KEY|SECRET|TOKEN|PASSWORD|CREDENTIALS)\\s*=\\s*)['\"]?[a-zA-Z0-9/+=_\\-]{20,}['\"]?",
             "[REDACTED:env-secret]"),
        ]

        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }

        return result
    }

    // MARK: - Stage 4: Size Guard

    static func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }

        // Truncate from the beginning (keep the most recent terminal output)
        let startIndex = text.index(text.endIndex, offsetBy: -maxLength)
        return "[...truncated, \(text.count - maxLength) chars omitted]\n"
            + String(text[startIndex...])
    }
}
#endif
