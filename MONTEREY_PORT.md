# macOS 12 (Monterey) port: status

Goal: run Light Touch on macOS 12. The upstream app targets macOS 14.4. This branch lowers every deployment target to 12.0
and replaces what that needs. **None of it has been compiled**; it was written without Xcode. Expect a round or two of
compile errors on the first build.

## What changed

| Needed macOS | Replaced by |
|---|---|
| 14: Observation (`@Observable`, `@Bindable`, `withObservationTracking`) | `swift-perception` 2.0.9 (`@Perceptible` …); SwiftUI bodies that read those models are wrapped in `WithPerceptionTracking` |
| 13: swift-subprocess | `Packages/SubprocessCompat`, a module also named `Subprocess` implementing the used subset on `Foundation.Process` |
| 13: `Duration`, `ContinuousClock`, `SuspendingClock`, `Task.sleep(for:)` | `Packages/HostCompat`: `HostDuration`, `HostContinuousClock`, `HostSuspendingClock`, `Task.hostSleep(for:)` |
| 13: `NSLock.withLock`, `OSAllocatedUnfairLock` | `HostCompat`: `hostWithLock`, `HostLock` |
| 13: Swift `Regex`, `firstRange(of:)` | `HostCompat`: `hostFirstMatch`/`hostMatches`/`hostWholeMatch` (NSRegularExpression), `hostFirstRange(of:)` |
| 13/14 SwiftUI/AppKit: `LabeledContent`, `Grid`, `.formStyle`, `.scrollDisabled`, 0-parameter `.onChange`, `NavigationSplitView`, `NSSplitViewItem(inspector…)`, `sizingOptions` | `LightTouchMac/UI/Compat12.swift` and `#available` fallbacks (a plainer look on 12) |

## Building

Xcode 26 needs macOS 15.6 or later: build on a newer Mac, then copy the app to the Monterey machine.
The first build asks you to trust the swift-perception macros (swift-syntax).

## Known open items

- `build-support/dependencies.json` still pins the native libraries as **arm64** only; an Intel/Monterey build needs
  x86_64 (or universal) static dependencies. Its deployment target is now 12.0.
- `tests/` packages and the Swift Testing suites still target macOS 14.4 and use the standard `Duration`; they were not ported.
- Further macOS 13+ API uses will show up as compile errors; fix them like the ones above.
- Behavior to check by eye on 12: grouped forms, the About licenses pane, the inspector pane, Add Device facts.
