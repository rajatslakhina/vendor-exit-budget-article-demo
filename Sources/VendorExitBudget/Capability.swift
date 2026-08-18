import Foundation

/// A single, discrete thing an inference provider either does or does not do.
///
/// Modelled as a closed enumeration rather than free-form strings on purpose. A capability
/// you cannot name is a capability you cannot budget for, and the whole point of this
/// library is to make the dependency countable.
public enum Capability: String, Sendable, Hashable, CaseIterable, Codable {
    /// Schema-constrained decoding: the provider guarantees output conforming to a supplied
    /// schema, rather than the caller parsing free text and hoping.
    case structuredOutput

    /// The model can request execution of caller-supplied functions and consume their results.
    case toolCalling

    /// Incremental token delivery, which UI affordances get built on top of.
    case streaming

    /// Image input.
    case vision

    /// A distinct, privileged instruction channel separate from user turns.
    case systemPrompt

    /// Per-token probabilities returned alongside the completion.
    case logprobs

    /// Executes without leaving the device. Not a performance property - a data-residency one.
    case onDevice

    /// A seed parameter that makes sampling reproducible for a fixed input.
    case deterministicSeed

    /// Human-facing label, used by the demo UI and by report rendering.
    public var label: String {
        switch self {
        case .structuredOutput: return "Structured output"
        case .toolCalling: return "Tool calling"
        case .streaming: return "Streaming"
        case .vision: return "Vision"
        case .systemPrompt: return "System prompt"
        case .logprobs: return "Logprobs"
        case .onDevice: return "On-device"
        case .deterministicSeed: return "Deterministic seed"
        }
    }
}

extension Capability: Comparable {
    /// Ordering exists purely so every report this library emits is byte-stable. Set iteration
    /// order is not guaranteed, and a report whose diff churns for no reason is a report
    /// nobody reads twice.
    public static func < (lhs: Capability, rhs: Capability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
