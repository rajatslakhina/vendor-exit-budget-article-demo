#if canImport(SwiftUI)
import SwiftUI

/// The demo screen: the two numbers side by side, and a switch that lets you feel the
/// binding capability move the whole plan.
@available(iOS 17.0, macOS 14.0, *)
public struct ExitBudgetView: View {
    @State private var requireOnDevice = true

    private var fleet: [CallSite] {
        requireOnDevice
            ? SampleFleet.callSites
            : SampleFleet.callSites.map { $0.dropping(.onDevice) }
    }

    private var plan: ExitPlan { SampleFleet.planner.plan(for: fleet) }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headline
                    lever
                    destinations
                    bindings
                    footnote
                }
                .padding(20)
            }
            .navigationTitle("Exit Budget")
        }
    }

    // MARK: - Sections

    private var headline: some View {
        let current = plan
        let gapIsWide = current.portabilityGap > 0.1
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                metric(
                    title: "Every call site\nhas an alternative",
                    value: percent(current.perSiteTrafficCoverage),
                    tint: Color.green
                )
                metric(
                    title: "Best single vendor\ncan actually take",
                    value: percent(current.bestSingleVendor?.trafficCoverage ?? 0),
                    tint: gapIsWide ? Color.red : Color.green
                )
            }
            Text("Portability gap: \(points(current.portabilityGap)) of traffic")
                .font(.headline)
                .foregroundStyle(gapIsWide ? Color.red : Color.secondary)
            Text("\(current.minimumVendorSet.count) vendors needed to cover the fleet · \(Int(current.exitCostDays.rounded())) engineer-days stranded")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .animation(.default, value: requireOnDevice)
    }

    private var lever: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Require on-device inference", isOn: $requireOnDevice)
                .font(.headline)
            Text("The binding capability. Two of ten call sites ask for it. Turn it off and watch which vendor wins.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var destinations: some View {
        let current = plan
        let winner = current.bestSingleVendor?.id
        return VStack(alignment: .leading, spacing: 12) {
            Text("If you had to move tonight")
                .font(.title3.bold())
            ForEach(current.rankedOptions) { option in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(option.displayName)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(percent(option.trafficCoverage))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.secondary)
                    }
                    ProgressView(value: min(max(option.trafficCoverage, 0), 1))
                        .tint(option.id == winner ? Color.accentColor : Color.gray)
                    Text("\(option.portedSiteIDs.count) of \(option.portedSiteIDs.count + option.strandedSiteIDs.count) call sites · \(Int(option.rewriteDays.rounded())) days to rewrite the rest")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .animation(.default, value: requireOnDevice)
    }

    private var bindings: some View {
        let current = plan
        return VStack(alignment: .leading, spacing: 12) {
            Text("What each capability costs you")
                .font(.title3.bold())
            ForEach(current.bindingCapabilities.prefix(4)) { binding in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(binding.capability.label)
                            .font(.subheadline.weight(.medium))
                        Text("\(binding.sitesRequiring) call sites · \(percent(binding.trafficShare)) of traffic")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Text("+\(points(binding.coverageGain))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(binding.coverageGain > 0.05 ? Color.red : Color.secondary)
                }
            }
        }
        .animation(.default, value: requireOnDevice)
    }

    private var footnote: some View {
        Text("This is a price list, not a to-do list. On-device inference is a data-residency decision, not a nice-to-have. The number only tells you what it costs in portability, so the trade gets made on purpose.")
            .font(.footnote)
            .foregroundStyle(Color.secondary)
    }

    // MARK: - Helpers

    private func metric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func points(_ value: Double) -> String {
        String(format: "%.1f pts", value * 100)
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    ExitBudgetView()
}
#endif
