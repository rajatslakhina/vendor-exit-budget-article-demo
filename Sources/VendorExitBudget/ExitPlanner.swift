import Foundation

/// Computes what a forced provider migration would actually cost.
///
/// The library exists because of one asymmetry: teams reason about portability *per call site*
/// ("could something else do this?") but they execute migrations *per vendor* ("we are moving
/// to one provider by Friday"). Those two questions have different answers, and only the
/// second one is a plan.
public struct ExitPlanner: Sendable {
    public let providers: [ProviderProfile]
    public let incumbentID: String

    /// - Parameters:
    ///   - providers: every provider under consideration, including the incumbent.
    ///   - incumbentID: id of the provider currently in production.
    public init(providers: [ProviderProfile], incumbentID: String) {
        self.providers = providers
        self.incumbentID = incumbentID
    }

    /// Non-incumbent providers, in stable id order.
    public var alternatives: [ProviderProfile] {
        providers.filter { $0.id != incumbentID }.sorted { $0.id < $1.id }
    }

    public func plan(for fleet: [CallSite]) -> ExitPlan {
        let sites = fleet.sorted { $0.id < $1.id }
        let others = alternatives

        // A call site nobody in the market can serve is a correctness problem, not a
        // portability one. Leaving it in the denominator would quietly punish every vendor
        // for a requirement none of them could ever meet.
        let unservable = sites.filter { site in
            !providers.contains { $0.satisfies(site) }
        }
        let unservableIDs = Set(unservable.map(\.id))
        let servable = sites.filter { !unservableIDs.contains($0.id) }

        let denominator = weight(of: servable)

        let perSite = share(
            of: servable.filter { site in others.contains { $0.satisfies(site) } },
            over: denominator
        )

        let ranked = rankOptions(over: servable, denominator: denominator, using: others)
        let bestCoverage = ranked.first?.trafficCoverage ?? 0

        let binding = bindingCapabilities(
            over: servable,
            denominator: denominator,
            using: others,
            baseline: bestCoverage
        )

        // Capability-clean but context-stranded: no alternative can run it, yet at least one
        // alternative already meets every capability it asks for. Relaxing requirements will
        // never recover these, so they are reported separately rather than folded into the
        // binding-capability list where they would imply a fix that does not exist.
        let contextBound = servable.filter { site in
            guard !others.contains(where: { $0.satisfies(site) }) else { return false }
            return others.contains { $0.shortfall(for: site).isContextOnly }
        }

        return ExitPlan(
            incumbentID: incumbentID,
            perSiteTrafficCoverage: perSite,
            rankedOptions: ranked,
            portabilityGap: perSite - bestCoverage,
            bindingCapabilities: binding,
            minimumVendorSet: minimumVendorSet(covering: servable, using: others),
            unservableSiteIDs: unservable.map(\.id),
            contextBoundSiteIDs: contextBound.map(\.id)
        )
    }

    // MARK: - Ranking

    private func rankOptions(
        over sites: [CallSite],
        denominator: Double,
        using others: [ProviderProfile]
    ) -> [SingleVendorOption] {
        others.map { provider in
            let ported = sites.filter { provider.satisfies($0) }
            let stranded = sites.filter { !provider.satisfies($0) }
            return SingleVendorOption(
                id: provider.id,
                displayName: provider.displayName,
                portedSiteIDs: ported.map(\.id),
                strandedSiteIDs: stranded.map(\.id),
                trafficCoverage: share(of: ported, over: denominator),
                rewriteDays: stranded.reduce(0) { $0 + $1.rewriteDays }
            )
        }
        .sorted { lhs, rhs in
            // Total order, so the report is reproducible run to run.
            if lhs.trafficCoverage != rhs.trafficCoverage { return lhs.trafficCoverage > rhs.trafficCoverage }
            if lhs.rewriteDays != rhs.rewriteDays { return lhs.rewriteDays < rhs.rewriteDays }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Counterfactual

    private func bindingCapabilities(
        over sites: [CallSite],
        denominator: Double,
        using others: [ProviderProfile],
        baseline: Double
    ) -> [BindingCapability] {
        let inUse = Set(sites.flatMap(\.required)).sorted()

        return inUse.map { capability in
            let dependents = sites.filter { $0.required.contains(capability) }
            let relaxed = sites.map { $0.dropping(capability) }

            // Re-solve from scratch. The best destination is allowed to change when a
            // requirement disappears, and holding the incumbent-best vendor fixed here would
            // systematically under-report the capability that matters most.
            let bestRelaxed = rankOptions(over: relaxed, denominator: denominator, using: others)
                .first?.trafficCoverage ?? 0

            return BindingCapability(
                capability: capability,
                sitesRequiring: dependents.count,
                trafficShare: share(of: dependents, over: denominator),
                coverageIfDropped: bestRelaxed,
                coverageGain: max(0, bestRelaxed - baseline)
            )
        }
        .sorted { lhs, rhs in
            if lhs.coverageGain != rhs.coverageGain { return lhs.coverageGain > rhs.coverageGain }
            if lhs.trafficShare != rhs.trafficShare { return lhs.trafficShare > rhs.trafficShare }
            return lhs.capability < rhs.capability
        }
    }

    // MARK: - Set cover

    /// Greedy maximum-traffic-first cover. Greedy is an approximation for set cover, not an
    /// optimum, so treat a result of N as "no fewer than N is obvious", not "N is provably
    /// minimal". It is still the number worth putting in front of a staff meeting.
    private func minimumVendorSet(covering sites: [CallSite], using others: [ProviderProfile]) -> [String] {
        var uncovered = sites
        var chosen: [String] = []

        while !uncovered.isEmpty {
            var best: (provider: ProviderProfile, covered: [CallSite])?

            for provider in others where !chosen.contains(provider.id) {
                let covered = uncovered.filter { provider.satisfies($0) }
                guard !covered.isEmpty else { continue }
                if let current = best {
                    let gain = weight(of: covered)
                    let incumbentGain = weight(of: current.covered)
                    if gain > incumbentGain || (gain == incumbentGain && provider.id < current.provider.id) {
                        best = (provider, covered)
                    }
                } else {
                    best = (provider, covered)
                }
            }

            // No remaining provider covers anything still uncovered. Those call sites are
            // stranded under every possible destination; stop rather than spin.
            guard let pick = best else { break }
            chosen.append(pick.provider.id)
            let taken = Set(pick.covered.map(\.id))
            uncovered.removeAll { taken.contains($0.id) }
        }

        return chosen
    }

    // MARK: - Weighting

    /// Total monthly calls. Used as the coverage denominator.
    private func weight(of sites: [CallSite]) -> Double {
        sites.reduce(0.0) { $0 + Double($1.monthlyCalls) }
    }

    /// Traffic-weighted share, with an explicit fallback.
    ///
    /// When the fleet carries no recorded traffic at all - a fresh app, or a fleet defined
    /// before instrumentation - weighting by zero would make every provider look identical.
    /// In that case each call site counts once instead. Reporting `0` there would be a lie
    /// dressed as arithmetic.
    private func share(of subset: [CallSite], over denominator: Double) -> Double {
        guard denominator > 0 else { return 0 }
        return weight(of: subset) / denominator
    }
}

extension ExitPlanner {
    /// Convenience entry point that applies the unweighted fallback described above by
    /// substituting a call of 1 for every site when the fleet records no traffic.
    public func planCountingSitesEquallyIfUntrafficked(for fleet: [CallSite]) -> ExitPlan {
        let total = fleet.reduce(0) { $0 + $1.monthlyCalls }
        guard total == 0 else { return plan(for: fleet) }
        let normalised = fleet.map {
            CallSite(
                id: $0.id,
                feature: $0.feature,
                required: $0.required,
                minimumContextTokens: $0.minimumContextTokens,
                monthlyCalls: 1,
                rewriteDays: $0.rewriteDays
            )
        }
        return plan(for: normalised)
    }
}
