# VendorExitBudget

**Measuring what it would actually cost to change model vendors — as a number, not a feeling.**

Every team shipping LLM features says the same sentence: *"we put an abstraction in front of it, so we can swap providers."* This library exists to test that claim, because an abstraction is not portability. Portability is a property of what your call sites depend on, and almost nobody has counted.

The distinction it measures:

- **Per-site portability** — "does *something* out there satisfy this call site?" This is the number an abstraction layer encourages you to quote.
- **Single-vendor portability** — "if we had to move to *one* provider tonight, how much of our traffic actually goes?" This is the only one that is a plan.

On the sample fleet in `SampleFleet.swift` — ten call sites, 3,817,000 monthly calls, five providers — those two numbers are **100.0%** and **61.8%**.

![Ranked destinations for a forced migration. The on-device foundation model takes 61.8% of traffic on 4 of 10 call sites; self-hosted open weights takes 59.8% on 7 of 10; Frontier Cloud B 56.5%; managed private cloud 47.7%. A callout notes that counting call sites and weighting traffic pick different winners, and that the traffic winner is not the cheapest landing.](Docs/destinations.png)

---

## What it computes

```swift
let planner = ExitPlanner(providers: SampleFleet.providers, incumbentID: "frontier-a")
let plan = planner.plan(for: SampleFleet.callSites)

plan.perSiteTrafficCoverage        // 1.0    — every call site has somewhere to go
plan.bestSingleVendor?.id          // "device-fm"
plan.bestSingleVendor?.trafficCoverage  // 0.6183
plan.portabilityGap                // 0.3817 — 38.2 points between the two
plan.minimumVendorSet              // ["device-fm", "self-hosted", "frontier-b"]
plan.exitCostDays                  // 34.0
```

### The binding capability

The most useful output is not a score, it is a ranked price list. For every capability your call sites require, `bindingCapabilities` reports what coverage would return if that requirement disappeared — **re-solving the best destination from scratch**, because relaxing a requirement can hand the migration to a different vendor entirely.

```swift
let binding = plan.bindingCapabilities[0]
binding.capability        // .onDevice
binding.sitesRequiring    // 2
binding.trafficShare      // 0.3773
binding.coverageIfDropped // 0.9751
binding.coverageGain      // 0.3568 — 35.7 points, from two call sites
```

![Capability price list. On-device is required by 2 call sites and 37.73% of traffic and is worth 35.68 points of coverage; logprobs and vision are worth 0.45 points each; system prompt, structured output, streaming, tool calling and deterministic seed are worth zero. A callout reads "Frequency is not risk."](Docs/capability-price-list.png)

`systemPrompt` is required by nine of ten call sites and 98.95% of traffic and is worth **exactly zero** — every provider ships it. Requirement frequency is not a risk signal.

This is a price list, not a to-do list. On-device inference is a data-residency decision; the number only tells you what it costs in portability so the trade gets made deliberately.

---

## Design decisions worth arguing with

- **Traffic weighting, not call-site counting.** They disagree here: by count the best destination is `self-hosted` (7 of 10 sites), by traffic it is `device-fm` (4 of 10). The mechanism is concentration, not popularity: `inbox.triage` alone is 36.7% of all traffic and exactly one alternative can serve it.
- **Context window is a scalar, not a capability.** A shortfall of 96,000 tokens cannot be argued away by relaxing a requirement, so context-only stranding is reported separately in `contextBoundSiteIDs` rather than folded into the binding list, where it would imply a fix that does not exist.
- **Call sites nobody can serve are excluded from the denominator.** They are a correctness problem, not a portability one, and leaving them in would punish every vendor for a requirement none could meet.
- **The counterfactual re-solves the winner.** Holding the current best vendor fixed while dropping a requirement systematically under-reports the capability that matters most. There is a test for exactly this (`testBindingCapabilityRecomputesTheWinningVendorRatherThanHoldingItFixed`).
- **Greedy set cover is an approximation.** `minimumVendorSet` returning 3 means "no fewer than 3 is obvious", not "3 is provably minimal".
- **Every ordering is a total order.** Ties break deterministically by id, so the report does not churn between runs.

---

## How to run it

```bash
git clone https://github.com/rajatslakhina/vendor-exit-budget-article-demo.git
cd vendor-exit-budget-article-demo
open Demo/Demo.xcodeproj   # pick any iOS Simulator, then Build & Run
```

One repo, one clone, no second package to fetch — `Demo/Demo.xcodeproj` consumes the library through a local Swift package reference to `..`, which resolves to this repository root where `Package.swift` lives.

The demo screen shows the two headline numbers side by side and a single switch: **Require on-device inference**. Turning it off recomputes the whole plan live — coverage jumps 61.8% → 97.5% and the winning destination changes from the on-device model to self-hosted open weights.

Library only, no Xcode:

```bash
swift build && swift test
```

---

## Verification status

Stated plainly rather than implied:

- ✅ `swift build` and `swift test` both pass — **29 tests, 0 failures**, on Swift 6.0.3 (Linux aarch64). Edge cases covered: empty fleet, zero-traffic fleet, no alternatives at all, unservable call sites, context-only stranding, negative-input clamping, determinism across repeated runs.
- ✅ `ArticleClaimsTests.swift` asserts every number quoted in the article and in this README against the real computation, so prose and code cannot drift apart silently.
- ⚠️ `Demo/Demo.xcodeproj/project.pbxproj` was hand-authored. What was checked is only structural: brace and paren balance zero, nineteen objects defined, zero dangling object references, a shared `Demo.xcscheme` committed, and no `.executableTarget` anywhere in `Package.swift`. **That is not evidence Xcode can resolve the package or produce a build** — nobody has opened this project. The layout deliberately nests the project one level down so the `XCLocalSwiftPackageReference` at `..` points at the package root rather than at an ancestor of itself, which is the arrangement Xcode accepts.
- ❌ **The app was NOT run on the Simulator and there are no screenshots.** This demo was produced by an unattended scheduled run, and the desktop-automation permission needed to drive Xcode returned *"can't be approved during a scheduled run"* — there was no user present to approve it. `ExitBudgetView.swift` has therefore **never been compiled by any Swift compiler**: it is behind `#if canImport(SwiftUI)`, which is false on Linux. It was reviewed by hand against iOS 17 API availability instead (one real type error was caught that way — a ternary mixing `Color` and `HierarchicalShapeStyle` in `foregroundStyle`). Treat the SwiftUI layer as unverified.

Everything outside `ExitBudgetView.swift` is compiled and tested.

---

## Article

Written up in full here: **[Every Call Site Was Portable. The App Was Not.](https://medium.com/@er.rajatlakhina/every-call-site-was-portable-the-app-was-not-8c34f6f31e7f)**

## Licence

MIT — see [LICENSE](LICENSE).
