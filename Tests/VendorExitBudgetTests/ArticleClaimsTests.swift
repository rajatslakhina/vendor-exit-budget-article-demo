import XCTest
@testable import VendorExitBudget

/// Every number stated in the accompanying article is asserted here against the real
/// computation. If an edit to the library moves a figure, this suite fails and the prose
/// is wrong - which is the only way to stop an article and its demo drifting apart quietly.
final class ArticleClaimsTests: XCTestCase {

    private let plan = SampleFleet.plan

    func testFleetShape() {
        XCTAssertEqual(SampleFleet.callSites.count, 10)
        XCTAssertEqual(SampleFleet.providers.count, 5)
        XCTAssertEqual(SampleFleet.planner.alternatives.count, 4)
        XCTAssertEqual(SampleFleet.monthlyCalls, 3_817_000)
    }

    func testEveryCallSiteHasSomewhereToGo() {
        XCTAssertEqual(plan.perSiteTrafficCoverage, 1.0, accuracy: 1e-9)
        XCTAssertTrue(plan.unservableSiteIDs.isEmpty)
    }

    func testBestSingleVendorCoversJustUnderSixtyTwoPercentOfTraffic() throws {
        let best = try XCTUnwrap(plan.bestSingleVendor)
        XCTAssertEqual(best.id, "device-fm")
        XCTAssertEqual(best.trafficCoverage, 0.618286, accuracy: 1e-5)   // 61.83%
        XCTAssertEqual(plan.portabilityGap, 0.381713, accuracy: 1e-5)    // 38.17 points
        XCTAssertEqual(plan.exitCostDays, 34.0, accuracy: 1e-9)
    }

    /// The winner by traffic is not the winner by call-site count. Counting call sites picks
    /// `self-hosted` (7 of 10); weighting by traffic picks `device-fm` (4 of 10).
    func testSiteCountingAndTrafficWeightingDisagreeAboutTheDestination() throws {
        let byTraffic = try XCTUnwrap(plan.bestSingleVendor)
        let byCount = try XCTUnwrap(plan.rankedOptions.max { $0.portedSiteIDs.count < $1.portedSiteIDs.count })
        XCTAssertEqual(byTraffic.id, "device-fm")
        XCTAssertEqual(byTraffic.portedSiteIDs.count, 4)
        XCTAssertEqual(byCount.id, "self-hosted")
        XCTAssertEqual(byCount.portedSiteIDs.count, 7)
        XCTAssertNotEqual(byTraffic.id, byCount.id)
    }

    /// Coverage and rewrite cost rank differently too: the highest-coverage destination is
    /// not the cheapest one to land on.
    func testHighestCoverageDestinationIsNotTheCheapestOne() throws {
        let best = try XCTUnwrap(plan.bestSingleVendor)
        let cheapest = try XCTUnwrap(plan.rankedOptions.min { $0.rewriteDays < $1.rewriteDays })
        XCTAssertEqual(cheapest.id, "self-hosted")
        XCTAssertEqual(cheapest.rewriteDays, 24.0, accuracy: 1e-9)
        XCTAssertEqual(best.rewriteDays, 34.0, accuracy: 1e-9)
        XCTAssertGreaterThan(best.rewriteDays, cheapest.rewriteDays)
    }

    func testOnDeviceIsTheBindingCapabilityAndDroppingItChangesTheDestination() throws {
        let binding = try XCTUnwrap(plan.bindingCapabilities.first)
        XCTAssertEqual(binding.capability, .onDevice)
        XCTAssertEqual(binding.sitesRequiring, 2)
        XCTAssertEqual(binding.trafficShare, 0.377260, accuracy: 1e-5)     // 37.73%
        XCTAssertEqual(binding.coverageIfDropped, 0.975111, accuracy: 1e-5) // 97.51%
        XCTAssertEqual(binding.coverageGain, 0.356825, accuracy: 1e-5)      // 35.68 points

        // Relaxing it does not just raise the incumbent favourite's score - it hands the
        // migration to a different vendor entirely.
        let relaxed = SampleFleet.planner.plan(for: SampleFleet.callSites.map { $0.dropping(.onDevice) })
        XCTAssertEqual(relaxed.bestSingleVendor?.id, "self-hosted")
        XCTAssertNotEqual(relaxed.bestSingleVendor?.id, plan.bestSingleVendor?.id)
    }

    /// The capability nearly every call site asks for is the one that costs nothing, because
    /// every provider ships it. Requirement frequency is not a risk signal.
    func testMostRequiredCapabilityCostsNothing() throws {
        let systemPrompt = try XCTUnwrap(plan.bindingCapabilities.first { $0.capability == .systemPrompt })
        XCTAssertEqual(systemPrompt.sitesRequiring, 9)
        XCTAssertEqual(systemPrompt.trafficShare, 0.989521, accuracy: 1e-5) // 98.95%
        XCTAssertEqual(systemPrompt.coverageGain, 0, accuracy: 1e-9)

        let mostRequired = try XCTUnwrap(plan.bindingCapabilities.max { $0.sitesRequiring < $1.sitesRequiring })
        XCTAssertEqual(mostRequired.capability, .systemPrompt)
        XCTAssertNotEqual(mostRequired.capability, plan.bindingCapabilities[0].capability)
    }

    /// Everything other than `onDevice` is worth less than half a point of coverage.
    func testEveryOtherCapabilityIsNearlyFree() {
        for binding in plan.bindingCapabilities.dropFirst() {
            XCTAssertLessThan(binding.coverageGain, 0.005)
        }
    }

    func testThereIsNoSingleMigrationOnlyAThreeVendorOne() {
        XCTAssertEqual(plan.minimumVendorSet, ["device-fm", "self-hosted", "frontier-b"])
        XCTAssertEqual(plan.minimumVendorSet.count, 3)
    }

    /// The two next-most-binding capabilities are worth 0.45 points each, and they tie -
    /// which is why the tie-break by traffic share puts logprobs above vision.
    func testRunnersUpAreWorthLessThanHalfAPointEach() throws {
        let logprobs = try XCTUnwrap(plan.bindingCapabilities.first { $0.capability == .logprobs })
        let vision = try XCTUnwrap(plan.bindingCapabilities.first { $0.capability == .vision })
        XCTAssertEqual(logprobs.coverageGain, 0.004454, accuracy: 1e-5)   // +0.45 pts
        XCTAssertEqual(vision.coverageGain, 0.004454, accuracy: 1e-5)     // +0.45 pts
        XCTAssertEqual(logprobs.coverageIfDropped, 0.622740, accuracy: 1e-5)
        XCTAssertEqual(vision.coverageIfDropped, 0.622740, accuracy: 1e-5)
        XCTAssertEqual(logprobs.trafficShare, 0.058161, accuracy: 1e-5)
        XCTAssertEqual(vision.trafficShare, 0.024889, accuracy: 1e-5)
        // Equal gain, so traffic share decides the order.
        XCTAssertLessThan(
            plan.bindingCapabilities.firstIndex(of: logprobs)!,
            plan.bindingCapabilities.firstIndex(of: vision)!
        )
    }

    /// Ported-site counts as printed in the destinations chart.
    func testPortedSiteCountsAreExactlyAsCharted() {
        XCTAssertEqual(plan.rankedOptions.map(\.portedSiteIDs.count), [4, 7, 6, 3])
        XCTAssertEqual(plan.rankedOptions.map(\.rewriteDays), [34, 24, 30, 50])
    }

    /// The headline flip is caused by concentration, not by a correlation between
    /// portability and popularity: one call site is over a third of all traffic and has
    /// exactly one possible destination.
    func testOneCallSiteCarriesOverAThirdOfTrafficAndHasASingleDestination() throws {
        let triage = try XCTUnwrap(SampleFleet.callSites.first { $0.id == "inbox.triage" })
        let share = Double(triage.monthlyCalls) / Double(SampleFleet.monthlyCalls)
        XCTAssertEqual(share, 0.366780, accuracy: 1e-5)   // 36.68%
        let takers = SampleFleet.planner.alternatives.filter { $0.satisfies(triage) }
        XCTAssertEqual(takers.map(\.id), ["device-fm"])
    }

    /// Rarity is not risk either: `toolCalling` is required by exactly two call sites,
    /// same as `onDevice`, and is worth nothing because every provider ships it.
    func testACapabilityCanBeRareAndStillFree() throws {
        let tools = try XCTUnwrap(plan.bindingCapabilities.first { $0.capability == .toolCalling })
        let onDevice = try XCTUnwrap(plan.bindingCapabilities.first { $0.capability == .onDevice })
        XCTAssertEqual(tools.sitesRequiring, 2)
        XCTAssertEqual(onDevice.sitesRequiring, 2)
        XCTAssertEqual(tools.coverageGain, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(onDevice.coverageGain, 0.35)
        XCTAssertTrue(SampleFleet.planner.alternatives.allSatisfy { $0.capabilities.contains(.toolCalling) })
    }

    func testRankingOfEveryDestinationIsExactlyAsPublished() {
        XCTAssertEqual(plan.rankedOptions.map(\.id), ["device-fm", "self-hosted", "frontier-b", "managed-pcc"])
        let coverages = plan.rankedOptions.map { ($0.trafficCoverage * 10_000).rounded() / 100 }
        XCTAssertEqual(coverages, [61.83, 59.79, 56.46, 47.68])
    }
}
