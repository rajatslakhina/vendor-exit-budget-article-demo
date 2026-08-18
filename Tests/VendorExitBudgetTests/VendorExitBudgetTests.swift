import XCTest
@testable import VendorExitBudget

final class VendorExitBudgetTests: XCTestCase {

    // MARK: - Fixtures

    private func provider(
        _ id: String,
        _ caps: Set<Capability>,
        context: Int = 128_000
    ) -> ProviderProfile {
        ProviderProfile(id: id, displayName: id.uppercased(), capabilities: caps, maxContextTokens: context)
    }

    private func site(
        _ id: String,
        _ caps: Set<Capability>,
        context: Int = 8_000,
        calls: Int = 1_000,
        days: Double = 1
    ) -> CallSite {
        CallSite(
            id: id, feature: "F",
            required: caps,
            minimumContextTokens: context,
            monthlyCalls: calls,
            rewriteDays: days
        )
    }

    // MARK: - Satisfaction

    func testProviderSatisfiesOnlyWhenCapabilitiesAndContextBothClear() {
        let p = provider("p", [.streaming, .systemPrompt], context: 16_000)
        XCTAssertTrue(p.satisfies(site("a", [.streaming], context: 16_000)))
        XCTAssertFalse(p.satisfies(site("b", [.streaming, .vision], context: 16_000)))
        XCTAssertFalse(p.satisfies(site("c", [.streaming], context: 16_001)))
    }

    func testShortfallSeparatesCapabilityGapsFromContextGaps() {
        let p = provider("p", [.streaming], context: 8_000)
        let mixed = p.shortfall(for: site("a", [.streaming, .vision], context: 32_000))
        XCTAssertEqual(mixed.missingCapabilities, [.vision])
        XCTAssertEqual(mixed.contextShortfallTokens, 24_000)
        XCTAssertFalse(mixed.isContextOnly)

        let contextOnly = p.shortfall(for: site("b", [.streaming], context: 32_000))
        XCTAssertTrue(contextOnly.isContextOnly)
        XCTAssertEqual(contextOnly.missingCapabilities, [])

        XCTAssertTrue(p.shortfall(for: site("c", [.streaming], context: 8_000)).isSatisfied)
    }

    // MARK: - The gap this library exists to measure

    func testPerSiteCoverageCanBeTotalWhileNoSingleVendorComesClose() {
        // Two call sites, each portable, but to mutually exclusive destinations.
        let planner = ExitPlanner(
            providers: [
                provider("home", [.streaming, .vision, .logprobs]),
                provider("x", [.streaming, .vision]),
                provider("y", [.streaming, .logprobs])
            ],
            incumbentID: "home"
        )
        let plan = planner.plan(for: [
            site("uses-vision", [.vision], calls: 500),
            site("uses-logprobs", [.logprobs], calls: 500)
        ])

        XCTAssertEqual(plan.perSiteTrafficCoverage, 1.0, accuracy: 1e-9)
        XCTAssertEqual(plan.bestSingleVendor?.trafficCoverage ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(plan.portabilityGap, 0.5, accuracy: 1e-9)
        XCTAssertEqual(plan.minimumVendorSet.count, 2)
    }

    func testCoverageIsTrafficWeightedNotSiteCounted() {
        let planner = ExitPlanner(
            providers: [
                provider("home", [.streaming, .vision]),
                provider("x", [.streaming])
            ],
            incumbentID: "home"
        )
        // Nine tiny portable sites, one enormous stranded one.
        var fleet = (0..<9).map { site("small\($0)", [.streaming], calls: 10) }
        fleet.append(site("huge", [.vision], calls: 910))
        let plan = planner.plan(for: fleet)

        // Site-counted this would read 90%. Traffic-weighted it is 9%.
        XCTAssertEqual(plan.bestSingleVendor?.trafficCoverage ?? 0, 0.09, accuracy: 1e-9)
    }

    // MARK: - Binding capabilities

    func testBindingCapabilityRecomputesTheWinningVendorRatherThanHoldingItFixed() throws {
        // `home` is incumbent. `narrow` wins today only because it alone has `.onDevice`.
        // Drop `.onDevice` and `broad` should overtake it - a fixed-vendor counterfactual
        // would report a gain of zero here.
        let planner = ExitPlanner(
            providers: [
                provider("home", [.streaming]),
                provider("narrow", [.onDevice, .structuredOutput]),
                provider("broad", [.structuredOutput, .streaming, .vision])
            ],
            incumbentID: "home"
        )
        let plan = planner.plan(for: [
            site("private", [.onDevice, .structuredOutput], calls: 600),
            site("public", [.structuredOutput, .vision], calls: 400)
        ])

        XCTAssertEqual(plan.bestSingleVendor?.id, "narrow")
        XCTAssertEqual(plan.bestSingleVendor?.trafficCoverage ?? 0, 0.6, accuracy: 1e-9)

        let onDevice = try XCTUnwrap(plan.bindingCapabilities.first { $0.capability == .onDevice })
        XCTAssertEqual(onDevice.coverageIfDropped, 1.0, accuracy: 1e-9)
        XCTAssertEqual(onDevice.coverageGain, 0.4, accuracy: 1e-9)
        XCTAssertEqual(plan.bindingCapabilities.first?.capability, .onDevice)
    }

    func testCapabilityEveryProviderOffersIsRankedAsFree() {
        let planner = ExitPlanner(
            providers: [
                provider("home", [.streaming, .systemPrompt]),
                provider("x", [.streaming, .systemPrompt]),
                provider("y", [.streaming, .systemPrompt])
            ],
            incumbentID: "home"
        )
        let plan = planner.plan(for: [site("a", [.streaming, .systemPrompt], calls: 100)])
        for binding in plan.bindingCapabilities {
            XCTAssertEqual(binding.coverageGain, 0, accuracy: 1e-9)
        }
    }

    func testBindingListIsDeterministicAcrossRepeatedRuns() {
        let first = SampleFleet.plan.bindingCapabilities.map(\.capability)
        let second = SampleFleet.plan.bindingCapabilities.map(\.capability)
        XCTAssertEqual(first, second)
        XCTAssertEqual(SampleFleet.plan.rankedOptions.map(\.id), SampleFleet.plan.rankedOptions.map(\.id))
    }

    // MARK: - Edge cases

    func testCallSiteNoProviderCanServeIsExcludedFromCoverageMath() {
        let planner = ExitPlanner(
            providers: [
                provider("home", [.streaming]),
                provider("x", [.streaming])
            ],
            incumbentID: "home"
        )
        let plan = planner.plan(for: [
            site("ok", [.streaming], calls: 100),
            site("impossible", [.vision, .logprobs, .onDevice], calls: 900)
        ])

        XCTAssertEqual(plan.unservableSiteIDs, ["impossible"])
        // Coverage is 100% of what could ever have moved, not 10% of everything.
        XCTAssertEqual(plan.bestSingleVendor?.trafficCoverage ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertFalse(plan.bestSingleVendor?.strandedSiteIDs.contains("impossible") ?? true)
    }

    func testContextOnlyStrandingIsReportedSeparatelyFromCapabilityStranding() {
        let planner = ExitPlanner(
            providers: [
                provider("home", [.streaming], context: 200_000),
                provider("x", [.streaming], context: 8_000)
            ],
            incumbentID: "home"
        )
        let plan = planner.plan(for: [site("long", [.streaming], context: 100_000, calls: 10)])

        XCTAssertEqual(plan.contextBoundSiteIDs, ["long"])
        // Nothing on the binding list can recover it, because no capability is missing.
        for binding in plan.bindingCapabilities {
            XCTAssertEqual(binding.coverageGain, 0, accuracy: 1e-9)
        }
    }

    func testNoAlternativesAtAllYieldsZeroCoverageRatherThanCrashing() {
        let planner = ExitPlanner(providers: [provider("home", [.streaming])], incumbentID: "home")
        let plan = planner.plan(for: [site("a", [.streaming], calls: 10)])

        XCTAssertNil(plan.bestSingleVendor)
        XCTAssertEqual(plan.perSiteTrafficCoverage, 0, accuracy: 1e-9)
        XCTAssertEqual(plan.exitCostDays, 0, accuracy: 1e-9)
        XCTAssertTrue(plan.minimumVendorSet.isEmpty)
    }

    func testEmptyFleetIsAnsweredNotDividedByZero() {
        let planner = ExitPlanner(
            providers: [provider("home", [.streaming]), provider("x", [.streaming])],
            incumbentID: "home"
        )
        let plan = planner.plan(for: [])
        XCTAssertEqual(plan.perSiteTrafficCoverage, 0, accuracy: 1e-9)
        XCTAssertEqual(plan.portabilityGap, 0, accuracy: 1e-9)
        XCTAssertTrue(plan.unservableSiteIDs.isEmpty)
    }

    func testUntraffickedFleetFallsBackToCountingSitesEqually() {
        let planner = ExitPlanner(
            providers: [
                provider("home", [.streaming, .vision]),
                provider("x", [.streaming])
            ],
            incumbentID: "home"
        )
        let fleet = [
            site("a", [.streaming], calls: 0),
            site("b", [.vision], calls: 0)
        ]

        // Weighted by zero traffic, every provider looks identical at 0%.
        XCTAssertEqual(planner.plan(for: fleet).bestSingleVendor?.trafficCoverage ?? -1, 0, accuracy: 1e-9)
        // Counting sites equally, the honest answer is half.
        let fallback = planner.planCountingSitesEquallyIfUntrafficked(for: fleet)
        XCTAssertEqual(fallback.bestSingleVendor?.trafficCoverage ?? 0, 0.5, accuracy: 1e-9)
    }

    func testNegativeInputsAreClampedRatherThanTrusted() {
        let s = CallSite(
            id: "x", feature: "F", required: [.streaming],
            minimumContextTokens: -5, monthlyCalls: -20, rewriteDays: -3
        )
        XCTAssertEqual(s.minimumContextTokens, 0)
        XCTAssertEqual(s.monthlyCalls, 0)
        XCTAssertEqual(s.rewriteDays, 0, accuracy: 1e-9)
        XCTAssertEqual(ProviderProfile(id: "p", displayName: "P", capabilities: [], maxContextTokens: -9).maxContextTokens, 0)
    }

    func testMinimumVendorSetStopsWhenNoProviderCanCoverTheRemainder() {
        let planner = ExitPlanner(
            providers: [
                provider("home", [.streaming, .vision]),
                provider("x", [.streaming])
            ],
            incumbentID: "home"
        )
        // `only-home` is servable (the incumbent can do it) but no alternative can.
        let plan = planner.plan(for: [
            site("portable", [.streaming], calls: 100),
            site("only-home", [.vision], calls: 100)
        ])
        XCTAssertEqual(plan.minimumVendorSet, ["x"])
        XCTAssertEqual(plan.perSiteTrafficCoverage, 0.5, accuracy: 1e-9)
    }

    func testDroppingACapabilityNeverMutatesTheCallerSFleet() {
        let original = site("a", [.streaming, .vision])
        let relaxed = original.dropping(.vision)
        XCTAssertEqual(original.required, [.streaming, .vision])
        XCTAssertEqual(relaxed.required, [.streaming])
        XCTAssertEqual(relaxed.monthlyCalls, original.monthlyCalls)
    }
}
