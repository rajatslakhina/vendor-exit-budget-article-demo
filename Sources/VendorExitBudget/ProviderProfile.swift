import Foundation

/// What one inference provider offers, flattened to the only two things that decide
/// whether a call site can move: the capability set and the context ceiling.
public struct ProviderProfile: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let displayName: String
    public let capabilities: Set<Capability>
    public let maxContextTokens: Int

    public init(id: String, displayName: String, capabilities: Set<Capability>, maxContextTokens: Int) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.maxContextTokens = max(0, maxContextTokens)
    }

    /// Whether this provider can run the call site unchanged.
    public func satisfies(_ site: CallSite) -> Bool {
        site.required.isSubset(of: capabilities) && maxContextTokens >= site.minimumContextTokens
    }

    /// Why it cannot, when it cannot. Empty means it can.
    public func shortfall(for site: CallSite) -> Shortfall {
        Shortfall(
            missingCapabilities: site.required.subtracting(capabilities),
            contextShortfallTokens: max(0, site.minimumContextTokens - maxContextTokens)
        )
    }

    /// A structured reason a provider cannot take a call site.
    public struct Shortfall: Sendable, Hashable, Codable {
        public let missingCapabilities: Set<Capability>
        public let contextShortfallTokens: Int

        public var isSatisfied: Bool {
            missingCapabilities.isEmpty && contextShortfallTokens == 0
        }

        /// True when the only thing standing in the way is the context ceiling.
        ///
        /// This distinction is load-bearing: relaxing capability requirements can never fix
        /// a context shortfall, so these call sites are immune to the counterfactual in
        /// `ExitPlan.bindingCapabilities` and must not be counted as recoverable there.
        public var isContextOnly: Bool {
            missingCapabilities.isEmpty && contextShortfallTokens > 0
        }

        /// Deterministic ordering for rendering.
        public var sortedMissing: [Capability] { missingCapabilities.sorted() }
    }
}
