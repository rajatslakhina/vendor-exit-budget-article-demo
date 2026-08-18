import Foundation

/// A deliberately ordinary mail-and-search app: ten call sites, one incumbent, four
/// plausible destinations. Nothing here is exotic. That is the point - the portability
/// cliff shows up in a fleet no one would flag in review.
public enum SampleFleet {
    public static let incumbentID = "frontier-a"

    public static let providers: [ProviderProfile] = [
        ProviderProfile(
            id: "frontier-a",
            displayName: "Frontier Cloud A (incumbent)",
            capabilities: [.structuredOutput, .toolCalling, .streaming, .vision, .systemPrompt, .logprobs],
            maxContextTokens: 200_000
        ),
        ProviderProfile(
            id: "device-fm",
            displayName: "On-device foundation model",
            capabilities: [.structuredOutput, .toolCalling, .streaming, .systemPrompt, .onDevice],
            maxContextTokens: 8_000
        ),
        ProviderProfile(
            id: "managed-pcc",
            displayName: "Managed private cloud",
            capabilities: [.structuredOutput, .toolCalling, .streaming, .systemPrompt],
            maxContextTokens: 32_000
        ),
        ProviderProfile(
            id: "frontier-b",
            displayName: "Frontier Cloud B",
            capabilities: [.structuredOutput, .toolCalling, .streaming, .vision, .systemPrompt, .deterministicSeed],
            maxContextTokens: 1_000_000
        ),
        ProviderProfile(
            id: "self-hosted",
            displayName: "Self-hosted open weights",
            capabilities: [.structuredOutput, .toolCalling, .streaming, .systemPrompt, .logprobs, .deterministicSeed],
            maxContextTokens: 128_000
        )
    ]

    public static let callSites: [CallSite] = [
        CallSite(
            id: "agent.actions", feature: "Agent",
            required: [.toolCalling, .streaming, .structuredOutput, .systemPrompt],
            minimumContextTokens: 64_000, monthlyCalls: 60_000, rewriteDays: 9
        ),
        CallSite(
            id: "compose.rewrite", feature: "Compose",
            required: [.streaming, .systemPrompt],
            minimumContextTokens: 8_000, monthlyCalls: 620_000, rewriteDays: 2
        ),
        CallSite(
            id: "compose.tone", feature: "Compose",
            required: [.structuredOutput, .systemPrompt],
            minimumContextTokens: 4_000, monthlyCalls: 300_000, rewriteDays: 1.5
        ),
        CallSite(
            id: "eval.judge", feature: "Quality",
            required: [.logprobs, .deterministicSeed, .structuredOutput, .systemPrompt],
            minimumContextTokens: 32_000, monthlyCalls: 12_000, rewriteDays: 4
        ),
        CallSite(
            id: "inbox.summary", feature: "Inbox",
            required: [.streaming, .systemPrompt],
            minimumContextTokens: 16_000, monthlyCalls: 900_000, rewriteDays: 2
        ),
        CallSite(
            id: "inbox.triage", feature: "Inbox",
            required: [.onDevice, .structuredOutput, .systemPrompt],
            minimumContextTokens: 8_000, monthlyCalls: 1_400_000, rewriteDays: 6
        ),
        CallSite(
            id: "privacy.redact", feature: "Privacy",
            required: [.onDevice, .structuredOutput],
            minimumContextTokens: 4_000, monthlyCalls: 40_000, rewriteDays: 12
        ),
        CallSite(
            id: "scan.receipt", feature: "Scan",
            required: [.vision, .structuredOutput, .systemPrompt],
            minimumContextTokens: 16_000, monthlyCalls: 95_000, rewriteDays: 6
        ),
        CallSite(
            id: "search.answer", feature: "Search",
            required: [.streaming, .toolCalling, .systemPrompt],
            minimumContextTokens: 128_000, monthlyCalls: 180_000, rewriteDays: 5
        ),
        CallSite(
            id: "search.rerank", feature: "Search",
            required: [.structuredOutput, .logprobs, .systemPrompt],
            minimumContextTokens: 32_000, monthlyCalls: 210_000, rewriteDays: 8
        )
    ]

    public static var planner: ExitPlanner {
        ExitPlanner(providers: providers, incumbentID: incumbentID)
    }

    public static var plan: ExitPlan {
        planner.plan(for: callSites)
    }

    /// Total monthly calls across the sample fleet.
    public static var monthlyCalls: Int {
        callSites.reduce(0) { $0 + $1.monthlyCalls }
    }
}
