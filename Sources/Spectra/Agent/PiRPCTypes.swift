import Foundation

// MARK: - Commands (stdin → Pi)

/// Send a user prompt to the Pi agent.
/// Pi RPC docs: `message` field (NOT `content`). Events do NOT carry request id.
struct PiRPCPromptCommand: Encodable {
    let type = "prompt"
    let message: String

    init(message: String) {
        self.message = message
    }
}

/// Abort the current agent operation.
struct PiRPCAbortCommand: Encodable {
    let type = "abort"
}

/// Query the current session state (used for readiness check).
struct PiRPCGetStateCommand: Encodable {
    let type = "get_state"
}

// MARK: - Events (Pi → stdout)

/// Top-level event wrapper parsed from each JSONL line.
/// Pi events are heterogeneous — we decode the `type` field first, then parse the rest.
enum PiRPCEvent {
    case response(command: String, success: Bool, error: String?)
    case agentStart
    case agentEnd(assistantText: String?)
    case turnStart
    case turnEnd
    case messageStart(role: String)
    case messageEnd(usage: PiTokenUsage?)
    case messageUpdate(PiAssistantMessageEvent)
    case toolExecutionStart(name: String)
    case toolExecutionEnd(exitCode: Int?)
    case error(String)
    case unknown(type: String)
}

/// Sub-events within `message_update.assistantMessageEvent`.
enum PiAssistantMessageEvent {
    case textStart(contentIndex: Int)
    case textDelta(String)
    case textEnd(content: String)
    case thinkingStart
    case thinkingDelta(String)
    case thinkingEnd
    case done(reason: String)     // "stop", "length", "toolUse"
    case eventError(reason: String) // "aborted", "error"
}

/// Token usage extracted from message_end or turn_end.
struct PiTokenUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let totalTokens: Int
}

// MARK: - JSONL Parsing

enum PiRPCEventParser {

    /// Parse a single JSONL line into a PiRPCEvent.
    /// Returns nil for unparseable lines (logged by caller).
    static func parse(line: String) -> PiRPCEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "response":
            let command = json["command"] as? String ?? ""
            let success = json["success"] as? Bool ?? false
            let error = json["error"] as? String
            return .response(command: command, success: success, error: error)

        case "agent_start":
            return .agentStart

        case "agent_end":
            let text = extractAssistantText(from: json)
            return .agentEnd(assistantText: text)

        case "turn_start":
            return .turnStart

        case "turn_end":
            return .turnEnd

        case "message_start":
            let msg = json["message"] as? [String: Any]
            let role = msg?["role"] as? String ?? "unknown"
            return .messageStart(role: role)

        case "message_end":
            let msg = json["message"] as? [String: Any]
            let usage = parseUsage(from: msg)
            return .messageEnd(usage: usage)

        case "message_update":
            if let event = parseAssistantMessageEvent(from: json) {
                return .messageUpdate(event)
            }
            return .unknown(type: "message_update")

        case "tool_execution_start":
            let name = json["name"] as? String ?? "unknown"
            return .toolExecutionStart(name: name)

        case "tool_execution_end":
            let code = json["exitCode"] as? Int
            return .toolExecutionEnd(exitCode: code)

        default:
            return .unknown(type: type)
        }
    }

    // MARK: - Private Helpers

    private static func parseAssistantMessageEvent(from json: [String: Any]) -> PiAssistantMessageEvent? {
        guard let ame = json["assistantMessageEvent"] as? [String: Any],
              let subType = ame["type"] as? String else {
            return nil
        }

        switch subType {
        case "text_start":
            let idx = ame["contentIndex"] as? Int ?? 0
            return .textStart(contentIndex: idx)

        case "text_delta":
            let delta = ame["delta"] as? String ?? ""
            return .textDelta(delta)

        case "text_end":
            let content = ame["content"] as? String ?? ""
            return .textEnd(content: content)

        case "thinking_start":
            return .thinkingStart

        case "thinking_delta":
            let delta = ame["delta"] as? String ?? ""
            return .thinkingDelta(delta)

        case "thinking_end":
            return .thinkingEnd

        case "done":
            let reason = ame["reason"] as? String
                ?? (ame["partial"] as? [String: Any])?["stopReason"] as? String
                ?? "stop"
            return .done(reason: reason)

        case "error":
            let reason = ame["reason"] as? String ?? "unknown"
            return .eventError(reason: reason)

        default:
            return nil
        }
    }

    /// Extract final assistant text from agent_end messages array.
    private static func extractAssistantText(from json: [String: Any]) -> String? {
        guard let messages = json["messages"] as? [[String: Any]] else { return nil }
        for msg in messages.reversed() {
            guard (msg["role"] as? String) == "assistant",
                  let content = msg["content"] as? [[String: Any]] else { continue }
            for block in content {
                if (block["type"] as? String) == "text",
                   let text = block["text"] as? String {
                    return text
                }
            }
        }
        return nil
    }

    private static func parseUsage(from message: [String: Any]?) -> PiTokenUsage? {
        guard let usage = message?["usage"] as? [String: Any] else { return nil }
        return PiTokenUsage(
            inputTokens: usage["input"] as? Int ?? 0,
            outputTokens: usage["output"] as? Int ?? 0,
            cacheReadTokens: usage["cacheRead"] as? Int ?? 0,
            cacheWriteTokens: usage["cacheWrite"] as? Int ?? 0,
            totalTokens: usage["totalTokens"] as? Int ?? 0
        )
    }
}
