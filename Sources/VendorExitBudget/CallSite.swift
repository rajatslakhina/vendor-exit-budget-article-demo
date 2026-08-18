import Foundation

/// One place in the app where a model actually gets called.
///
/// The unit of portability analysis is the call site, not the feature and not the app.
/// Teams reason about portability at the app level ("we have an abstraction") while the
/// dependency is contracted one call site at a time.
public struct CallSite: Sendable, Hashable, Identifiable, Codable {
    /// Stable identifier, e.g. `"inbox.triage"`. Used for deterministic ordering.
    public let id: String

    /// The product surface this call site belongs to. Several call sites can share a feature.
    public let feature: String

    /// Everything the provider must do for this call site to work as written.
    public let required: Set<Capability>

    /// The smallest context window this call site can run in.
    ///
    /// Deliberately a scalar and not a `Capability`. A scalar shortfall cannot be argued away
    /// by relaxing a requirement, and conflating the two is how portability reports end up
    /// promising fixes that do not exist.
    public let minimumContextTokens: Int

    /// Traffic weight. Coverage that ignores volume flatters you: the call sites that are
    /// easiest to port are usually the ones nobody uses.
    public let monthlyCalls: Int

    /// Engineer-days to make this call site work on a provider that does not satisfy it -
    /// re-prompting, re-testing, building the missing guarantee by hand, or cutting the feature.
    public let rewriteDays: Double

    public init(
        id: String,
        feature: String,
        required: Set<Capability>,
        minimumContextTokens: Int,
        monthlyCalls: Int,
        rewriteDays: Double
    ) {
        self.id = id
        self.feature = feature
        self.required = required
        self.minimumContextTokens = max(0, minimumContextTokens)
        self.monthlyCalls = max(0, monthlyCalls)
        self.rewriteDays = max(0, rewriteDays)
    }

    /// The same call site with one capability requirement removed. Used by the counterfactual
    /// analysis in `ExitPlanner`; never mutates the caller's fleet.
    public func dropping(_ capability: Capability) -> CallSite {
        var relaxed = required
        relaxed.remove(capability)
        return CallSite(
            id: id,
            feature: feature,
            required: relaxed,
            minimumContextTokens: minimumContextTokens,
            monthlyCalls: monthlyCalls,
            rewriteDays: rewriteDays
        )
    }
}
