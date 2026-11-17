# Migrate between native stores

Status: Accepted and implemented
Date: 2026-09-15

## Context

PersistentKeyValueKit gives consumers one typed interface for `UserDefaults`,
`NSUbiquitousKeyValueStore`, and the in-memory store. The interface is useful
because generic code can work with any of those stores without branching on the
concrete type. Consumers should also be able to build their own abstractions on
top of that interface.

The package owns the supported Apple store integrations. It can know about
Foundation domains, identities, storage formats, and observation rules inside
those implementations. Supporting arbitrary third-party storage engines is not
a requirement. `InMemoryPersistentKeyValueStore` exists for testing and
convenience.

Representations own conversion between a Swift value and the object stored by a
backend. Migration must use those existing representations, including proxy
representations and consumer-provided conversion closures. A migration-specific
conversion protocol would split that contract and make custom representations
harder to compose.

Migration is uncommon. It must not reshape ordinary reads, writes, observation,
property wrappers, or store creation for every caller. At the same time,
migration needs persisted-value provenance. An effective `UserDefaults` read
can include registration defaults, launch arguments, and added suites, so it is
not enough to copy whatever the ordinary typed getter returns.

The public Foundation API does not provide a writable-domain getter for a
`UserDefaults` instance. `persistentDomain(forName:)` reads the domain named by
the caller; it does not attest that the name is the instance's writable domain.
The factory therefore records the name at the same time it creates the native
instance.

The project also requires blanket 100% line and region coverage for production
code. Coverage is a project constraint, not a reason to reduce behavioral
assertions.

## Decision

Migration is exposed through `PersistentKeyValueStore`. A named suite that will
participate in migration is created with:

```swift
guard let appGroup = UserDefaults.migratable(suiteName: "group.example.app") else {
    return
}

let report = try UserDefaults.standard.move(
    [.runtimeColorScheme],
    to: appGroup,
    onConflict: .keepBoth,
    tracking: .untracked
)
```

`UserDefaults.migratable(suiteName:)` calls Foundation's suite initializer and
returns that same native `UserDefaults` instance. It returns `nil` when the
domain is invalid or Foundation cannot create the native store. The optional
return deliberately follows Foundation's failable `UserDefaults(suiteName:)`
initializer instead of introducing construction errors. The factory attaches
the suite name as immutable, process-local metadata using an Objective-C
associated object. The metadata is associated with the instance, contains no
preference data, does not retain the store, and is not a public replacement for
`UserDefaults`.

`UserDefaults.standard` is recognized automatically when the application
bundle identifier is available; without one, migrating `UserDefaults.standard`
throws `PersistentKeyMigrationError.missingApplicationIdentifier`.
`NSUbiquitousKeyValueStore.default` and `InMemoryPersistentKeyValueStore` do
not need a separate migration construction step. A non-standard `UserDefaults`
instance created directly through Foundation remains valid for ordinary
storage, but migration throws `PersistentKeyMigrationError.missingMigrationDomain`
before mutation because the framework cannot identify its persistent domain.

The public migration operation stays generic. Its opaque, throwing endpoint
requirement is part of `PersistentKeyValueStore`; wrappers forward it to their
backing store with `try base.migrationEndpoint`. Endpoint construction, backend
identity, snapshots, and verification remain internal. Checked representation
conversion remains public. Migration does not intercept a wrapper's ordinary
`get` or `set` behavior.

## Why this design

The first implementation used public migration adapters. They provided the
information needed for persisted-only reads and verification, but callers had
to construct a second object for a store they already owned. Renaming those
adapters as participants did not remove the duplicated suite configuration.
Ordinary domain-aware wrappers were rejected primarily because they replace the
exact native objects that are central to this library's consumer-facing vision.
A wrapper created with a domain name can bind that name to the object it creates;
that does not make it the right abstraction for consumers who need the native
object itself.

The factory puts the one piece of Foundation knowledge at the point where the
native store is created. Generic code receives the same `UserDefaults` value it
would have received otherwise. This is a small, migration-only construction
concession rather than a rule that native stores should be replaced or wrapped.
The spelling `migratable(suiteName:)` is an ergonomic choice. It does not imply
that every factory should use that name or that `make` is forbidden.

Several tempting shortcuts were rejected:

- Equal dictionaries or equal values do not bind a declared domain to a native
  object. If the source's actual domain is A and both A and B contain `K = 1`,
  a source declared as A and a destination whose actual domain is A but is
  declared as B can appear to verify successfully. A move can then remove `K`
  from actual domain A.
- Effective reads can see values from added suites. A completion marker found
  in an added suite can make a migration look complete even though the
  migration never wrote that store.

The first is a reasoned alias trace. The second is supported by runtime probes,
as is the observation that a sentinel visible through reciprocal
`addSuite(named:)` paths proves visibility, not writable-domain identity or
object aliasing. These are not a mathematical impossibility proof. Runtime
probes on macOS 26.6.2 with Swift
6.3.3, Xcode 26.6, and the macOS 26.5 SDK verified the associated-object
mechanism, native dynamic type, protocol passage, lifetime cleanup, and the
behavior of untagged separate instances. The probes did not establish behavior
on every Apple platform or prove entitlement configuration.

## Consequences

- Generic consumer abstractions can migrate without knowing whether their
  stores are `UserDefaults`, `NSUbiquitousKeyValueStore`, or in-memory stores.
- Representations remain the single conversion boundary, including custom proxy
  representations.
- A named `UserDefaults` suite must opt in at construction time. This is a
  runtime capability, not a compile-time distinction, because the resulting
  value must remain a native `UserDefaults`.
- The metadata lasts only for the lifetime of that object in that process. It
  is not persisted and is not maintained in a global registry. Reconstructing a
  plain `UserDefaults` instance later does not recreate the migration capability.
- Migration remains non-transactional across stores. It can report a partial
  move, does not provide rollback, and cannot promise disk durability or cloud
  delivery.

The regression tests preserve these guarantees:

- [`MigrationNativeStoreTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationNativeStoreTests.swift)
  covers native identity, metadata ownership, domain validation, and concurrent access.
- [`MigrationNativeEndpointTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationNativeEndpointTests.swift)
  covers setup failures before storage access, suite aliases, added-suite fallbacks,
  and migration through generic and existential store types.
- [`PublicAPIClientTests`](../../Tests/PersistentKeyValueKitPublicAPITests/PublicAPIClientTests.swift)
  checks consumer composition without `@testable import`; compile-fail fixtures
  keep the endpoint opaque and the store requirement explicit.

The existing migration tests continue to cover representation conversion,
verification, conflict policies, observation, and partial failures.

## Reconsideration triggers

Revisit this decision if Foundation adds a supported way to obtain and verify a
`UserDefaults` instance's writable domain, or if the project's priorities about
native identity, generic composition, or migration guarantees change. Do not
revisit it merely by renaming the adapter or inferring identity from effective
values.

## References

- [`UserDefaults.init(suiteName:)`](https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:))
- [`UserDefaults.persistentDomain(forName:)`](https://developer.apple.com/documentation/foundation/userdefaults/persistentdomain(forname:))
- [`UserDefaults.addSuite(named:)`](https://developer.apple.com/documentation/foundation/userdefaults/addsuite(named:))
- [`objc_setAssociatedObject`](https://developer.apple.com/documentation/objectivec/objc_setassociatedobject(_:_:_:_:))
- [Associative References](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjectiveC/Chapters/ocAssociativeReferences.html)
