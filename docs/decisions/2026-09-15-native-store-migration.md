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
`UserDefaults` domain names are compared ignoring case and Unicode
normalization for migration identity and reserved-domain validation, and
`UserDefaults.migratable(suiteName:)` also rejects names containing `/`,
starting with `~`, or ending with `.plist` (in any case, checked by UTF-8 code
units). On case-insensitive
or normalization-insensitive file systems (the macOS default), suite names that
differ only by case or Unicode normalization, or that use path or `.plist`
aliases, can resolve to the same preferences file, so treating them as distinct
stores risked a move removing the values it had just written. Because this
comparison folds case and canonical equivalence on every platform, two
genuinely distinct suites on a case-sensitive volume whose names differ only by
case are also treated as one store, and migrations between them are rejected.

The public migration operation stays generic. Its opaque, throwing endpoint
requirement is part of `PersistentKeyValueStore`; wrappers forward it to their
backing store with `try base.migrationEndpoint`, and a wrapper that cannot
migrate throws its own error from `migrationEndpoint`, which propagates
unchanged. Endpoint construction, backend identity, snapshots, and verification
remain internal. Migration does not intercept a wrapper's ordinary `get` or
`set` behavior.

`copy` and `move` provide four overloads (for a single key, a single
`PersistentKeyMigrationItem`, an unlabeled `[any PersistentKeyProtocol]` array,
and a labeled `items: [PersistentKeyMigrationItem]` array), each requiring
explicit `onConflict:` and `tracking:` arguments (`PersistentKeyMigrationTracking.untracked`,
`.once(id:)` recorded in the destination store, or `.once(id:recordedIn:)`).
Completion marker keys (`PersistentKey.isMigrationCompleted(id:)`) normalize
`id` to Unicode Normalization Form C (NFC) before hashing with SHA-256 and
unpadded base64url encoding under the dotless prefix
`PersistentKeyValueKit_MigrationCompleted_`, so identifiers of any length fit
within `NSUbiquitousKeyValueStore`'s 128-UTF-16-code-unit key limit (84 UTF-16
code units) and can be observed directly by `UserDefaults` key-value
observation. `PersistentKeyMigrationItem` supports migrating a key unchanged
(`.key(_:)`), renaming a key of the same value type (`.key(_:to:)`), and
transforming a value across keys or types (`.key(_:to:transform:)`). Migrating
within a single store is permitted when every item either maps its source key
to a different destination key in that store or rewrites a key in place through
`.key(_:to:transform:)` on a single store instance with byte-identical source
and destination key identifiers (reporting `.rewritten` under any conflict
policy without removing the key as a source, and recognizing an
already-rewritten value on retry when it fails to decode with the source key's
representation and decodes with the destination key's representation); duplicate
source or destination key identifiers throw `duplicateKey(_:)`, and same-store
batches where one item's destination is another item's source throw
`overlappingKeys(_:)`.

`copy` and `move` return `PersistentKeyMigrationReport` and are not marked
`@discardableResult`. `PersistentKeyMigrationReport.Completion` and
`PersistentKeyMigrationReport.Status` (including `.rewritten` and
`.failed(FailureStage)`) are `Hashable`, while `completionError` and
`Outcome.error` carry any thrown error alongside the status.
`report.throwIfIncomplete()` throws `PersistentKeyMigrationIncompleteError`
carrying the report when any item or completion marker fails or goes
unrecorded. Public initializers on `PersistentKeyMigrationReport` and `Outcome`
remain available for test fixtures and enforce with preconditions that an error
is present if and only if the status is `.failed`, `outcomes` is empty for
`.alreadyRecorded`, `outcomes` contains at least one failed outcome for
`.notRecorded`, and `outcomes` contains no failed outcomes for `.recorded` or
`.failed`. Migration errors do not conform to `LocalizedError`.

`PersistentKeyValueRepresentation` and `PrimitiveKeyValuePersistible` require
checked `decode(storageObject:format:)` and `encode(_:format:)` /
`encode(format:)` methods. Both protocols provide default implementations of
their eight store- and container-specific `get` and `set` methods built on
those two conversions, while built-in representations and primitive types keep
their specialized implementations.

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

Subsequent refinements to the migration and representation APIs follow the same
principles:

- **No default for `tracking:`**: Whether a migration repeats on every call or
  records a persistent completion marker changes what later launches do, so the
  call site chooses `tracking:` explicitly.
- **The `items:` label on item batches**: Observed with Apple Swift 6.4.2
  (Xcode 27.2), having two unlabeled array overloads (`_ keys: [any PersistentKeyProtocol]`
  and `_ items: [PersistentKeyMigrationItem]`) made an empty literal
  `copy([], ...)` ambiguous, and a mixed literal missing `.key(...)` on one
  element failed type-checking with `"failed to produce diagnostic for
  expression"`. A refining-protocol alternative (`[any PersistentKeyMigrationEntry]`)
  also failed because implicit-member lookup on an existential element type did
  not resolve static key accessors constrained with `where Self == PersistentKey<T>`.
  Labeling the item overload `items:` lets `copy([], ...)` resolve unambiguously
  to `[any PersistentKeyProtocol]` (exercised by
  `MigrationReportTests.testEmptyBatchWithTrackingRecordsMarker`) and reports
  `"missing argument label 'items:'"` when `.key(...)` items are passed without
  the label (enforced by `Tests/CompileFail/UnlabeledItemBatch.swift` via
  `Scripts/check-public-api.sh`). The `"failed to produce diagnostic"` behavior
  and the refining-protocol experiment were observed during design and are not
  checked by automated tests.
- **Non-discardable `PersistentKeyMigrationReport`**: `copy` and `move` are not
  `@discardableResult`. Because per-item and completion-marker failures are
  recorded in the returned report rather than thrown, the unused-result warning
  nudges callers to inspect the report or call `try report.throwIfIncomplete()`.
- **Report and outcome shape (and fixture invariants)**:
  `PersistentKeyMigrationReport.Completion` and
  `PersistentKeyMigrationReport.Status` (including `.failed(FailureStage)`)
  conform to `Hashable` without embedding `any Error`, while `completionError`
  and `Outcome.error` carry the error alongside the status, following the
  precedent of `URLSessionTask.state` and `URLSessionTask.error`. Public
  initializers on `PersistentKeyMigrationReport` and `Outcome` are kept so
  callers can construct test fixtures, with preconditions that enforce every
  cross-field invariant the engine can produce: `error` and `completionError`
  are non-`nil` if and only if the status is `.failed`, `outcomes` is empty for
  `.alreadyRecorded`, `outcomes` contains at least one failed outcome for
  `.notRecorded`, and `outcomes` contains no failed outcomes for `.recorded` or
  `.failed`. `report.outcome(for:)` matches `sourceKeyID` by literal UTF-16 code
  units.
- **Same-store key mapping and `overlappingKeys`**: Migrating within a single
  store is allowed when every item maps its source key to a different
  destination key in that store, enabling in-place key renames and value
  transforms. Rejecting same-store batches where one item's destination is
  another item's source (`overlappingKeys(_:)`, such as `A -> B` and `B -> C`
  or `A -> B` and `B -> A`) guarantees that batch results do not depend on item
  order.
- **Representation defaults, container hooks in checked conversion, and the append-or-assign contract**:
  Providing default implementations of the eight store- and container-specific
  `get` and `set` methods on `PersistentKeyValueRepresentation` and
  `PrimitiveKeyValuePersistible` reduces custom conformances to two methods
  (`decode(storageObject:format:)` and `encode(_:format:)` /
  `encode(format:)`), while built-in representations and primitive types keep
  their specialized `get` and `set` overrides so `UserDefaults.argumentDomain`
  launch-argument string coercion and direct property-list container casting
  remain intact. Checked conversion for `Array` and `Dictionary`
  (`Array.decode`/`encode` and `Dictionary.decode`/`encode`, used by migration
  and `UserDefaults.register(_:)`) routes through the element or value
  representation's `get(from:)`, `set(_:to:)`, `get(_:from:)`, and
  `set(_:to:in:)` container hooks within a task-local `CheckedConversion` scope
  rather than calling scalar `decode` and `encode` element by element, because a
  per-element scratch path bypasses custom container formats (such as
  delta-coded arrays) and changes the meaning of stored elements. Within
  `CheckedConversion`, nested dictionary reads route through `Dictionary.decode`
  so undecodable entries fail instead of being omitted. Container write hooks
  receive an empty array (or a dictionary without `dictionaryKey`) and may
  either assign or append (preserving 1.x representations that append to
  `propertyListArray` instead of using a pre-seeded sentinel marker); an empty
  array result for non-empty input (or an absent dictionary entry) counts as a
  failure unless scalar `encode` returns `nil` for every element (or for the
  entry's value).
- **Storage-location contract (`PersistentKeyProtocol.id`)**: A key's value
  lives under its `id` in every store. Store-specific `PersistentKeyProtocol`
  methods (`get`, `set`, and `remove` on `UserDefaults`,
  `NSUbiquitousKeyValueStore`, and `InMemoryPersistentKeyValueStore`) customize
  how a value is read, written, or gated (such as clamping a value or locking
  `PersistentDebugKey` in Release builds), not where it is stored, so direct
  store access, observation, and migration operate on the same entry under `id`.
- **Removing `storeUnavailable` and omitting `LocalizedError`**: A store
  wrapper that cannot migrate throws its own error from `migrationEndpoint`,
  which propagates unchanged instead of being replaced by a generic
  `PersistentKeyMigrationError.storeUnavailable`. Migration errors do not
  conform to `LocalizedError` because they are developer diagnostics and the
  package ships no localized resources (its only bundled resource is
  `PrivacyInfo.xcprivacy`).
- **Suite alias rejection (`/`, `~`, and `.plist`)**: Core Foundation resolves
  suite names containing `/` (or starting with `~`) as file paths and strips a
  `.plist` suffix in any case, which lets two different suite names open the
  same preferences file under distinct domain identities (or cause
  `persistentDomain(forName:)` to read the wrong domain). `UserDefaults.migratable(suiteName:)`
  returns `nil` when `suiteName` contains `/`, starts with `~`, or ends with
  `.plist` (ignoring case), checking those delimiters by UTF-8 code units
  because a combining or prepended mark changes the Swift `Character` while Core
  Foundation still sees the ASCII delimiter, and compares domain names using
  case-folded Swift `String` equality (which also folds Unicode canonical
  equivalence).
- **Literal key identity (and the in-memory and dictionary-value exceptions)**:
  `UserDefaults` and `NSUbiquitousKeyValueStore` store and look up `NSString`
  keys by literal UTF-16 code units, whereas Swift `String` equality merges
  canonically equivalent spellings (such as NFC and NFD spellings of `"café"`).
  The package uses literal UTF-16 key identity across Foundation stores:
  `UserDefaultsMigrationBackend` sends `persistentDomain(forName:)` through
  Objective-C to keep the unbridged `NSDictionary` and looks up keys as
  `NSString`, `PropertyListMigrationStorage.equal` compares strings and
  dictionary keys with `NSString.isEqual` and `NSDictionary.object(forKey:)`,
  duplicate/overlap/`sameStore` validation in `UserDefaults` and
  `NSUbiquitousKeyValueStore` uses literal UTF-16 identity,
  `UserDefaults.register(_:)` builds an `NSMutableDictionary` keyed by
  `NSString`, launch-argument coercion looks up the literal key in the unbridged
  `UserDefaults.argumentDomain` dictionary, and Foundation observation
  deregistration, iCloud changed-key filtering, and `@PersistentValue`
  key-change detection compare key identifiers by UTF-16 code units. Two
  exceptions follow from Swift `String` storage: `InMemoryPersistentKeyValueStore`
  backs its storage with a Swift dictionary and therefore treats canonically
  equivalent key identifiers as one key in both storage and migration
  validation; and bridging a stored Foundation dictionary to `[String: Value]`
  collapses canonically equivalent `NSString` keys into one Swift key, so
  checked conversion (`Dictionary.decode`) rejects `NSDictionary` instances
  whose entry count shrinks on bridging (failing at `.decode` and keeping the
  source entry during migration), whereas ordinary `Dictionary` reads keep one
  entry (which one is unspecified).
- **Type-aware recursive snapshot verification, mutable in-memory references, and file URLs**:
  Core Foundation treats boolean `kCFBooleanTrue` and numeric `NSNumber(value: 1)`
  as equal under `==` and `CFEqual`, even though format-aware representations
  distinguish booleans, integers, and floating-point widths.
  `PropertyListMigrationStorage.equal` checks `CFBooleanGetTypeID()`,
  `CFNumberIsFloatType`, `CFNumberGetByteSize` (`Float` versus `Double`), `NaN`,
  and floating-point bit patterns (`0.0` versus `-0.0`) recursively across
  arrays and dictionaries. `UserDefaultsMigrationBackend` removes an existing
  key before writing when the replacement object is `CFEqual` to the snapshot
  but has a different property-list type so `UserDefaults` does not ignore the
  write, rechecking that the key is still absent after removal and failing at
  `.write` with `PersistentKeyMigrationError.destinationChanged` if an observer
  wrote during removal. Because `UserDefaults` stores file URLs as paths (which
  strips a non-existent directory's trailing slash or drops a file URL host),
  `UserDefaultsMigrationBackend.prepareMigrationWrite` verifies that decoding
  the frozen object reproduces `url.absoluteString` and fails at `.prepare` with
  `PersistentKeyValueConversionError.encodingFailed` before any mutation if it
  does not. In `InMemoryPersistentKeyValueStore`, snapshots freeze Foundation
  property-list objects (such as `NSMutableArray`) and compare their contents
  before writing or removing, while other reference types verify by revision
  only.
- **Post-cleanup destination recheck on `move`**: Removing a move's source key
  notifies synchronous observers, which can modify or delete the destination
  key before `move` returns. Both `.overwriteDestination` and
  `.keepDestinationAndRemoveSource` recheck the destination snapshot after
  removing the source and fail the item at `.cleanup` with
  `PersistentKeyMigrationError.destinationChanged` (suppressing completion
  recording) if the destination changed. Under `.keepDestinationAndRemoveSource`,
  `.failed(.cleanup)` with `.destinationChanged` also occurs before source
  removal if the preserved destination value changed since the initial snapshot
  (leaving the source in place); callers can read the source key to tell whether
  it was removed.
- **Same-store in-place rewrite via `.key(_:to:transform:)` (and retry/instance rules)**:
  An app that must keep an externally defined key name can upgrade its stored
  representation or value type in one checked, tracked step by passing
  `.key(k, to: k, transform:)` with byte-identical key identifiers
  (`source.id.utf8.elementsEqual(destination.id.utf8)`), using
  `transform: { $0 }` for a representation-only change. Every copy or move
  conflict policy rewrites the existing value in place without removing the key
  as a source and reports `.rewritten`, while `.key(k)` and `.key(k, to: k)`
  still throw `.sameStore`. A rewrite also requires `source` and `destination`
  to be the same store instance (`migrationHandle`), throwing `.sameStore` when
  two distinct instances alias one backing store (such as case-variant
  `UserDefaults` suite handles that can hold different cached values). Because a
  tracked batch replays from the start after a later item fails, a rewrite whose
  stored value fails to decode with `source`'s representation checks whether the
  snapshot decodes with `destination`'s representation and, if so, reports
  `.rewritten` without running `transform` or writing again. An in-place rewrite
  must therefore change the stored representation or use an idempotent
  transform, whereas same-format value changes (such as dollars to cents) should
  move to a new key identifier. The rule is based on the transform overload and
  literal key identity rather than comparing value types or representations
  because `PersistentKeyValueRepresentation` instances cannot be compared for
  equality.
- **Dotted-key `UserDefaults` monitor and observation scope**: Because
  key-value observation treats `.` as a key-path separator, dotted
  `UserDefaults` keys are observed through one `UserDefaultsKeyChangeMonitor`
  associated with each `UserDefaults` instance. The monitor installs its
  `UserDefaults.didChangeNotification` observer before the first read,
  deduplicates reads and comparison values per literal UTF-16 key identifier
  (fast-pathing identical cached non-`NSNumber` object references before
  `PropertyListMigrationStorage.equal`), and serializes reconciliation with a
  single-drainer loop that reads values and invokes callbacks outside its lock
  so concurrent notifications are drained by the active reconciler without stale
  reads overwriting newer comparison values. Because Foundation posts
  `didChangeNotification` only for in-process defaults writes and not for
  `addSuite(named:)` or `removeSuite(named:)`, dotted-key observation is scoped
  to in-process changes to `object(forKey:)`, and callbacks under concurrent
  writes can arrive on the reconciling thread.
- **NFC normalization of migration IDs and dotless completion markers**:
  `PersistentKey.isMigrationCompleted(id:)` normalizes `id` with
  `precomposedStringWithCanonicalMapping` (NFC) before SHA-256 hashing so
  migration IDs that compare equal as Swift strings share one completion
  marker, while case differences remain distinct. The marker prefix is
  `PersistentKeyValueKit_MigrationCompleted_` (no `.` characters, 84 UTF-16
  code units total) so `UserDefaults` key-value observation can observe marker
  keys directly.
- **Dictionary-read leniency versus strict migration (and all-or-nothing writes)**:
  Writes for both `Array` and `Dictionary` are all-or-nothing so a single
  unencodable element or entry leaves the existing stored collection unchanged.
  On ordinary reads, `Array` is all-or-nothing because element positions carry
  meaning, whereas `Dictionary` keeps readable entries and drops only
  undecodable ones so a single unknown entry (such as an enum case written by a
  newer app version) does not blank the whole dictionary. Checked conversion
  (`decode(storageObject:format:)`, used by migration) is strict for both
  `Array` and `Dictionary`, failing at `.decode` and preserving the source entry
  instead of silently dropping dictionary entries.
- **Privacy manifest (`PrivacyInfo.xcprivacy`) reasons**: The library ships
  `PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults`
  with reasons `CA92.1` and `1C8F.1`. Reason `C56D.1` is not declared because
  Apple disallows it for SDKs "created primarily to wrap required reason
  API(s)".

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
- [`MigrationKeyMappingTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationKeyMappingTests.swift),
  [`MigrationRewriteTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationRewriteTests.swift),
  [`MigrationNativeFidelityTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationNativeFidelityTests.swift),
  [`MigrationReportTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationReportTests.swift),
  and [`MigrationSetupValidationTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationSetupValidationTests.swift)
  cover same-store and cross-store key mapping, in-place rewrites, transforms,
  literal key and property-list type fidelity, post-cleanup rechecks, overlap
  and length validation, report invariants, and completion tracking.
- [`PersistentKeyValueRepresentationDefaultsTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key-Value%20Representation/PersistentKeyValueRepresentationDefaultsTests.swift),
  [`PrimitiveKeyValuePersistibleDefaultsTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/PrimitiveKeyValuePersistibleDefaultsTests.swift),
  [`CustomContainerHookTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/CustomContainerHookTests.swift),
  and [`CanonicallyEquivalentKeyTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/CanonicallyEquivalentKeyTests.swift)
  cover default store and container access built on `decode` and `encode`,
  custom container hooks and 1.x appending overrides, and literal versus
  canonical key identity across registration, launch arguments, and
  dictionaries.
- [`UserDefaultsKeyChangeObservationTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key-Value%20Store/UserDefaults/UserDefaultsKeyChangeObservationTests.swift)
  and [`NSUbiquitousKeyValueStoreObservationTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key-Value%20Store/NSUbiquitousKeyValueStore/NSUbiquitousKeyValueStoreObservationTests.swift)
  cover the per-instance dotted-key monitor, deduplicated reads, registration
  deregistration races, and literal key matching in observation.
- [`PublicAPIClientTests`](../../Tests/PersistentKeyValueKitPublicAPITests/PublicAPIClientTests.swift)
  checks consumer composition and the `id` storage-location contract without
  `@testable import`; compile-fail fixtures keep the endpoint opaque and enforce
  required protocol members, `tracking:`, and the `items:` label.

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
