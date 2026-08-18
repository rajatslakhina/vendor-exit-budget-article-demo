import Foundation

/// A single non-incumbent provider evaluated as *the* destination for a forced migration.
public struct SingleVendorOption: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let displayName: String
    /// Call sites this provider can take unchanged, in stable id order.
    public let portedSiteIDs: [String]
    /// Call sites it cannot, in stable id order.
    public let strandedSiteIDs: [String]
    /// Share of monthly calls that move. Traffic-weighted, not site-counted.
    public let trafficCoverage: Double
    /// Engineer-days to rewrite everything stranded.
    public let rewriteDays: Double
}

/// One capability, priced by what it actually costs you in portability.
public struct BindingCapability: Sendable, Hashable, Identifiable, Codable {
    public var id: Capability { capability }
    public let capability: Capability
    /// How many call sites declare it.
    public let sitesRequiring: Int
    /// Share of monthly calls flowing through those call sites.
    public let trafficShare: Double
    /// Traffic coverage of the best single vendor if this requirement vanished everywhere,
    /// re-solved from scratch - the winning vendor is allowed to change.
    public let coverageIfDropped: Double
    /// Improvement over the real best-single-vendor coverage. This is the number that ranks.
    public let coverageGain: Double
}

/// The output of an exit analysis.
public struct ExitPlan: Sendable, Hashable, Codable {
    public let incumbentID: String

    /// Share of traffic whose call site has *at least one* alternative somewhere in the market.
    /// The optimistic figure, and the one an abstraction layer encourages you to quote.
    public let perSiteTrafficCoverage: Double

    /// Every non-incumbent provider, ranked by traffic coverage then by id.
    public let rankedOptions: [SingleVendorOption]

    /// The best realistic destination, or `nil` when there are no alternatives at all.
    public var bestSingleVendor: SingleVendorOption? { rankedOptions.first }

    /// `perSiteTrafficCoverage` minus the best single vendor's coverage. The distance between
    /// the portability you can claim and the portability you can execute.
    public let portabilityGap: Double

    /// Capabilities ranked by how much coverage returns if you stop requiring them.
    public let bindingCapabilities: [BindingCapability]

    /// Smallest provider set covering every portable call site, greedily chosen. A count above
    /// one means no single migration exists, whatever the per-site number says.
    public let minimumVendorSet: [String]

    /// Call sites no provider in the fleet can serve, including the incumbent. These are not a
    /// portability problem; they are a correctness problem, and they are excluded from
    /// coverage denominators so they cannot flatter or damn a vendor unfairly.
    public let unservableSiteIDs: [String]

    /// Stranded call sites whose only obstacle is the context ceiling. No amount of
    /// requirement-relaxing recovers these.
    public let contextBoundSiteIDs: [String]

    /// Engineer-days implied by the best single vendor. Zero when nothing is stranded.
    public var exitCostDays: Double { bestSingleVendor?.rewriteDays ?? 0 }
}
