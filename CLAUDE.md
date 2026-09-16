# Repository Guidelines

This file is operating guidance for agents and contributors working in `PersistentKeyValueKit`. Keep changes small, explicit, and aligned with the package’s public API guarantees.

> [!IMPORTANT]
> Use relevant Agent Skills before changing Swift APIs, concurrency code, tests, or technical prose. They capture platform rules and local preferences that code search does not reliably reveal.

## Overview

`PersistentKeyValueKit` is a Swift Package Manager library for type-safe persistence on Apple platforms. It wraps `UserDefaults` and `NSUbiquitousKeyValueStore`, provides SwiftUI property wrappers, and exposes async observation for persistent key changes.

- **Swift tools version**: 6.2
- **Platforms**: `Package.swift` is the source of truth.
- **Product**: `PersistentKeyValueKit`
- **Tests**: XCTest
- **Runtime resources**: none

## Core Rules

Keep call sites typed and generic. Consumers define a key once, then use that key to read, write, bind, observe, or migrate values. The library's purpose is to let consumers build abstractions whose code does not branch on whether a value lives in `UserDefaults`, `NSUbiquitousKeyValueStore`, or an in-memory store. Do not close a generic API merely to simplify an implementation.

Representations are the ownership boundary for converting between a Swift value and a store's storage object. Higher-level features, including migration, consume the existing representation and proxy mechanisms; they must not introduce parallel, feature-specific conversion protocols. Custom proxy representations should work through their existing `from` and `to` conversions, including consumer-provided closures. Conversion may be repeated for validation, so do not promise purity or exact callback counts unless an API explicitly provides that guarantee.

We own the supported Apple store integrations and may encode knowledge of their native formats, domains, identities, observation, and other platform behavior in those implementations. `InMemoryPersistentKeyValueStore` exists for convenience and testing. That implementation knowledge does not make arbitrary third-party storage engines a required extension point, and it does not justify exposing Foundation details to callers.

Preserve exact native store objects while keeping consumer abstractions generic. Migration is uncommon and may require one opt-in construction step for a named `UserDefaults` suite; it must not replace ordinary native APIs or force concrete-store knowledge into generic code.

Treat public API changes as release decisions. Before adding requirements, changing defaults, renaming symbols, or raising platform minimums, identify the compatibility impact and document the reason.

Prefer required type contracts when core behavior must be checked and correct; representation conversion is one such contract. Do not use default "unsupported" implementations to avoid requiring a core capability. A breaking release can be the right way to establish such a contract, but a major-version boundary is not permission to break source compatibility without a concrete reason.

Do not leak Foundation storage quirks into user-facing APIs. Handle normalization, launch-argument coercion, observation filtering, cancellation, and deregistration inside the package.

Preserve the distinction between missing values and valid values such as `false` or `0`, so typed keys can apply their declared defaults. An unconditional `bool(forKey:)` loses that distinction; a bare `object(forKey:) as? Bool` rejects string-valued launch overrides.

UserDefaults launch arguments can contain strings for typed values. Keep their parsing scoped to `UserDefaults.argumentDomain`; do not extend it to arbitrary persisted strings. Optional and proxy representations must inherit this behavior without requiring consumer workarounds.

Store identity, migration, and representation boundaries are deliberate design constraints. Read the [native-store migration decision](docs/decisions/2026-09-15-native-store-migration.md) before changing them; it records the trade-offs and the evidence behind them.

## Repository Structure

```text
├── Package.swift
├── README.md
├── Sources/PersistentKeyValueKit/
│   ├── Async Sequence/
│   ├── Key-Value Persistible/
│   ├── Persistent Key/
│   ├── Persistent Key-Value Representation/
│   ├── Persistent Key-Value Store/
│   └── Property Wrapper/
└── Tests/PersistentKeyValueKitTests/
    ├── Scaffolding/
    └── Tests/
```

Source folders are grouped by feature area. Put new code beside the feature it extends. Keep reusable mocks, observable stores, and custom persistible types in `Tests/PersistentKeyValueKitTests/Scaffolding/`.

## Architecture

`PersistentKeyProtocol` models typed keys. `PersistentKeyValueStore` defines storage operations. `KeyValuePersistible` and `PersistentKeyValueRepresentation` define conversion between Swift values and property-list-compatible storage.

Public abstractions should remain composable while implementation mechanics stay private. For example, a consumer's generic store abstraction can forward a migration endpoint without knowing backend identities, revision tokens, or storage bookkeeping. Endpoint forwarding selects the backing store; it does not intercept a wrapper's ordinary `get` and `set` methods or replace the representation's conversion contract. Preserve ordinary storage behavior when adding higher-level operations.

Concrete stores stay close to their backing APIs. They may contain platform-specific knowledge, while shared typed behavior remains in the store and representation abstractions:

- `UserDefaults`: Foundation defaults plus KVO observation.
- `NSUbiquitousKeyValueStore`: iCloud key-value storage plus notification observation.
- `InMemoryPersistentKeyValueStore`: test and ephemeral storage.

Keep `PersistentValue` and `PersistentKeyValues` behavior aligned. SwiftUI observation and async observation should agree on defaults, emitted values, unrelated-key filtering, cancellation, and deregistration unless the difference is intentional and documented.

## Development Commands

Run from the repository root.

```sh
swift build
swift test
swift test --filter PersistentKeyValuesTests
swift test -c release
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency -Xswiftc -enable-actor-data-race-checks
```

Run the public API checks and the combined Debug and Release coverage gate on macOS:

```sh
bash Scripts/check-public-api.sh
swift test --enable-code-coverage
swift test -c release --enable-code-coverage
ruby Scripts/check-swift-coverage.rb \
    "$(swift build --show-bin-path)/codecov/PersistentKeyValueKit.json" \
    "$(swift build -c release --show-bin-path)/codecov/PersistentKeyValueKit.json"
```

Use the filtered command while iterating. Use strict-concurrency tests for observation, locking, cancellation, or sendability changes. Use release tests for performance-sensitive changes.

## Programming

Preserve existing Swift style: 4-space indentation, grouped declarations, and `// MARK:` sections. Public types use `UpperCamelCase`; properties, functions, and tests use `lowerCamelCase`.

Use the static accessor pattern for reusable keys:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Bool> {
    static var isFeatureEnabled: Self {
        Self("IsFeatureEnabled", defaultValue: false)
    }
}
```

Check availability before using new Apple APIs. Support every platform minimum in `Package.swift`, or add guarded fallbacks.

Do not add `Sendable` requirements to public value protocols unless the compatibility cost is intentional. Protect shared mutable state explicitly; Foundation store integrations should not force consumers into actor isolation.

Use comments for nonobvious whys only. Public documentation comments should describe behavioral contracts, especially observation lifetime, buffering, storage conversion, and compatibility constraints.

## Testing

Add focused XCTest coverage for every behavior change. Use unique keys such as `key:\(#function)` to avoid cross-test state leakage.

For store behavior, test each affected store. For async observation, cover initial emission, change-only streams, buffering, unrelated keys, cancellation, iterator deinitialization, deregistration, and concurrent cancellation/change races.

Exercise public APIs from a normal importing client, including generic and existential use where supported. Use compile-fail fixtures for boundaries that must remain inaccessible or required.

Maintain 100% line and region coverage across all production code. Coverage is not limited to new or changed code, and it is not a substitute for behavioral assertions.

## Contributing

Recent commits use short imperative subjects: `Fix UserDefaults launch argument parsing`, `Improve hot path performance`. Match that style and never credit tools or agents.

Before committing, run:

```sh
git log --oneline -10
git status --short
```

Pull requests must list behavior changes, test commands run, and any public API, platform minimum, concurrency, or versioning impact.

## Prose

Read surrounding prose before editing `README.md`, `AGENTS.md`, or long doc comments. Integrate changes into the document’s structure; do not append isolated notes. Tighten wording by default.

Watch for **phantom rationale**: prose that invents a reason for an API shape instead of stating the fact. If an API has two equivalent spellings, say that. Do not explain it with a fake workflow preference.

## Agent-Specific Instructions

Do not overwrite unrelated local changes. Commit when asked. Do not push unless explicitly requested.
