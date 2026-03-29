import Foundation
import GhosttyKit

/// Reads terminal viewport content via the libghostty C API.
///
/// Uses `ghostty_surface_read_text` to capture the visible viewport as plain text.
/// The raw text is passed through `TerminalContentSanitizer` before being sent
/// to external LLM providers.
enum TerminalBufferReader {

    /// Maximum characters to send to LLM (prevents excessive token usage).
    static let maxCaptureSize = 50_000

    /// Read the visible viewport as raw text (before sanitization).
    static func readViewport(from surface: ghostty_surface_t) -> String? {
        let size = ghostty_surface_size(surface)
        guard size.columns > 0, size.rows > 0 else { return nil }

        var selection = ghostty_selection_s()
        selection.top_left = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0,
            y: 0
        )
        selection.bottom_right = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: UInt32(size.columns) - 1,
            y: UInt32(size.rows) - 1
        )
        selection.rectangle = false

        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else {
            return nil
        }
        defer { ghostty_surface_free_text(surface, &text) }

        guard text.text_len > 0, let ptr = text.text else { return nil }
        return String(cString: ptr)
    }

    /// Read viewport and sanitize for external LLM consumption.
    static func readCleanViewport(from surface: ghostty_surface_t) -> String? {
        guard let raw = readViewport(from: surface) else { return nil }
        let sanitized = TerminalContentSanitizer.sanitize(raw, maxLength: maxCaptureSize)
        guard sanitized.count >= 10 else { return nil } // too short = effectively empty
        return sanitized
    }
}
