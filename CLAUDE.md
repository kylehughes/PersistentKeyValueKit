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

Keep call sites typed. Consumers define a key once, then use that key to read, write, bind, or observe values. Store internals stay inside the package.

Treat public API changes as release decisions. Before adding requirements, changing defaults, renaming symbols, or raising platform minimums, identify the compatibility impact and document the reason.

Do not leak Foundation storage quirks into user-facing APIs. Handle normalization, launch-argument coercion, observation filtering, cancellation, and deregistration inside the package.

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

Concrete stores stay thin:

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
