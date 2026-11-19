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
try report.throwIfIncomplete()
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
`UserDefaults.migratable(suiteName:)` also rejects names containing `/` or NUL,
starting with `~`, or ending with `.plist` (in any case, checked by UTF-8 code
units). On case-insensitive
or normalization-insensitive file systems (the macOS default), suite names that
differ only by case or Unicode normalization, or that use path, `.plist`, or
NUL-truncated aliases, can resolve to the same preferences domain, so treating
them as distinct stores risked a move removing the values it had just written.
Because this comparison folds case and canonical equivalence on every platform,
two genuinely distinct suites on a case-sensitive volume whose names differ
only by case are also treated as one store. Migrations between them follow the
same-store rules: disjoint key mappings are allowed, while same-key mappings and
overlapping batches are rejected.

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
within a single store is permitted when every item maps its source key to a
different destination key in that store; any same-store item whose source and
destination key identifiers are the same throws `sameStore` during setup before
any key is read (to change a key's stored representation or value format, move
it to a new key identifier), duplicate source or destination key identifiers
throw `duplicateKey(_:)`, and same-store batches where one item's destination
is another item's source throw `overlappingKeys(_:)`.

`copy` and `move` return `PersistentKeyMigrationReport` and are not marked
`@discardableResult`. `PersistentKeyMigrationReport.Completion` and
`PersistentKeyMigrationReport.Status` (including
`.failed(FailureStage)`) are `Hashable`, while `completionError` and
`Outcome.error` carry any thrown error alongside the status.
`report.throwIfIncomplete()` throws `PersistentKeyMigrationIncompleteError`
carrying the report when any item or completion marker fails or goes
unrecorded. Public initializers on `PersistentKeyMigrationReport`, `Outcome`, and
`PersistentKeyMigrationIncompleteError` remain available for test fixtures and
enforce with preconditions that an error is present if and only if the status is
`.failed`, `outcomes` is empty for `.alreadyRecorded`, `outcomes` contains at
least one failed outcome for `.notRecorded`, `outcomes` contains no failed
outcomes for `.recorded` or `.failed`, and
`PersistentKeyMigrationIncompleteError(report:)` receives a report with
`!report.isComplete`. Migration errors do not conform to `LocalizedError`.

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
  `@discardableResult`. Because per-item failures and failures to record the
  completion marker are reported rather than thrown, the unused-result warning
  nudges callers to inspect the report or call `try report.throwIfIncomplete()`.
  An existing marker that cannot decode as a `Bool` is different: it throws
  `invalidCompletionRecord` after the marker is read and before any item runs.
- **Report and outcome shape (and fixture invariants)**:
  `PersistentKeyMigrationReport.Completion` and
  `PersistentKeyMigrationReport.Status` (including `.failed(FailureStage)`)
  conform to `Hashable` without embedding `any Error`, while `completionError`
  and `Outcome.error` carry the error alongside the status, following the
  precedent of `URLSessionTask.state` and `URLSessionTask.error`. Public
  initializers on `PersistentKeyMigrationReport`, `Outcome`, and
  `PersistentKeyMigrationIncompleteError` are kept so callers can construct test
  fixtures, with preconditions that enforce every cross-field invariant the
  engine can produce: `error` and `completionError` are non-`nil` if and only if
  the status is `.failed`, `outcomes` is empty for `.alreadyRecorded`,
  `outcomes` contains at least one failed outcome for `.notRecorded`, `outcomes`
  contains no failed outcomes for `.recorded` or `.failed`, and
  `PersistentKeyMigrationIncompleteError(report:)` requires `!report.isComplete`.
  `report.outcome(for:)` matches `sourceKeyID` by literal UTF-16 code units.
- **Same-store key mapping and `overlappingKeys`**: Migrating within a single
  store is allowed when every item maps its source key to a different
  destination key in that store, enabling key renames and value transforms
  within that store while rejecting any same-store item whose source and
  destination key identifiers are the same with `sameStore` during setup.
  Rejecting same-store batches where one item's destination is another item's
  source (`overlappingKeys(_:)`, such as `A -> B` and `B -> C` or `A -> B` and
  `B -> A`) keeps an item from reading a value that another item in the batch
  wrote or removed. Items run in input order, and a `transform` can run before a
  later preparation or write failure.
- **Representation defaults, container hooks in checked conversion, and the append-or-assign contract**:
  Providing default implementations of the eight store- and container-specific
  `get` and `set` methods on `PersistentKeyValueRepresentation` and
  `PrimitiveKeyValuePersistible` reduces custom conformances to two methods
  (`decode(storageObject:format:)` and `encode(_:format:)` /
  `encode(format:)`), while built-in representations and primitive types keep
  their specialized `get` and `set` overrides so `UserDefaults.argumentDomain`
  launch-argument string coercion and direct property-list container casting
  remain intact. Ordinary collection writes (`propertyListArray(encoding:)`,
  `propertyListArrays(encoding:)`, `propertyListDictionary(encoding:)`, and
  `propertyListDictionaries(encoding:)`) route built-in `Optional` and proxy
  representations through `BuiltInValueOmission`
  (`builtInOrdinaryPropertyListArray(encoding:)`,
  `builtInOrdinaryPropertyListDictionary(encoding:)`, and
  `builtInOrdinaryDictionaryEntryWriter()` on
  `OptionalPersistentKeyValueRepresentation` and `BuiltInProxyConversion`),
  which unwraps optionals or converts each value to its proxy once and decides
  omission from that conversion (converting each dictionary entry through every
  wrapper layer before the next entry when wrapping another
  `BuiltInValueOmission` representation, or writing directly with
  `set(_:to:in:)` otherwise, so the first failing entry stops the write), while
  encoding any other representation directly with `set(_:to:)` or
  `set(_:to:in:)`. Converting each value once keeps both failed and all-omitted
  writes linear even for recursive proxy-over-optional types while keeping
  writes all-or-nothing. For `Array` and `Dictionary` checked
  conversion (`Array.decode`/`encode` and `Dictionary.decode`/`encode`, used by
  migration and `UserDefaults.register(_:)`), representations defined by the
  package (`PrimitivePersistentKeyValueRepresentation` for `Array` and
  `Dictionary`, `OptionalPersistentKeyValueRepresentation`,
  `ProxyPersistentKeyValueRepresentation`,
  `RawRepresentablePersistentKeyValueRepresentation`,
  `LosslessStringConvertiblePersistentKeyValueRepresentation`, and
  `CodablePersistentKeyValueRepresentation` via `BuiltInContainerConversion`,
  plus built-in scalar primitives via `BuiltInScalarPrimitive` and
  `BuiltInScalarConversion`) convert their containers through strict, linear
  checked paths on any thread without relying on ambient task-local state that
  can be lost across threads or leak into ordinary store reads inside a codec:
  when every representation in the conversion chain is built in and converts
  only built-in primitive types, checked array decoding finishes both storage
  decoding and proxy conversion for each element (`checkedValues(decoding:converting:)`)
  before reading the next so it rethrows the first element's error in input
  order, whereas checked encoding converts proxy layers first
  (`values.map(checkedProxy(for:))`) and can therefore report a later element's
  outer proxy error before an earlier element's inner encoding error (such as
  `EncodingError`). Representations defined outside the package (including
  custom `PersistentKeyValueRepresentation` or `PrimitiveKeyValuePersistible`
  conformances and consumer types conforming to
  `ProxyPersistentKeyValueRepresentationProtocol`), as well as
  `PrimitivePersistentKeyValueRepresentation` for a `PrimitiveKeyValuePersistible`
  type defined outside it, have their `get(from:)`, `set(_:to:)`,
  `get(_:from:)`, and `set(_:to:in:)` container methods called as written,
  whether overridden or inherited from the protocol default: an external array
  hook reads the whole array through `get(from:)` first (so even when wrapped
  in a built-in proxy representation, its `nil` return throws
  `PersistentKeyValueConversionError.invalidStorageValue` before any outer
  proxy converts an earlier element), a custom hook that drops undecodable
  elements drops them in migration too, and a consumer type conforming to
  `ProxyPersistentKeyValueRepresentationProtocol` over a `[String: Value]` proxy
  with default container methods delegates to `[String: Value]`'s container
  methods and reads nested dictionaries leniently. Container write hooks receive
  an empty array (or a dictionary without `dictionaryKey`): array hooks may
  only assign to or append to that empty array (preserving 1.x representations
  that append to `propertyListArray`), and dictionary hooks write only the
  entry for `dictionaryKey` without reading, modifying, adding, or removing
  other entries. On every collection write path (arrays, dictionaries, nested
  collections, and `Optional` or proxy paths, in both ordinary writes and
  checked `[T].encode` and `[String: T].encode` across all three formats),
  custom container hook output is validated against the store property-list
  allow-list (`storableSnapshot`), accepted mutable containers and mutable
  string/data leaves are copied recursively (dictionary keys are not copied,
  while default write paths pass plain Swift `String`, `Int`, `Double`, `Bool`,
  `Data`, and `Date` values as-is), and external dictionary hooks undergo a
  final completed-dictionary validation pass (`isStorableDictionary`) so
  altering an earlier entry during a later call cannot leave non-storable
  objects or uncopied mutables. Because an external
  representation's container methods report failure only by returning `nil`,
  leaving the array empty for non-empty input, or leaving `dictionaryKey`
  absent, and re-running conversion to reconstruct an error or check whether
  every element encoded to `nil` causes exponential work on recursive types,
  checked conversion throws the generic
  `PersistentKeyValueConversionError.invalidStorageValue` or `.encodingFailed`
  directly and ordinary collection writes distinguish omission from failure only
  through `BuiltInValueOmission` during the single conversion pass.
  Consequently, for representations defined outside the package, an entry left
  out by a container write hook counts as a failure: writing a dictionary in
  which a value's `encode` returns `nil` fails and leaves the store unchanged
  under the default hooks, as does a non-empty array whose every element
  encodes to `nil` (a custom hook can report success for such a value, and
  checked reads then use the hooks as implemented; package
  `OptionalPersistentKeyValueRepresentation` and package proxies over omitting
  representations conform to `BuiltInValueOmission`).
- **Storage-location contract (`PersistentKeyProtocol.id`)**: A key's value
  lives under its `id` in every store. Store-specific `PersistentKeyProtocol`
  methods (`get`, `set`, and `remove` on `UserDefaults`,
  `NSUbiquitousKeyValueStore`, and `InMemoryPersistentKeyValueStore`) customize
  how a value is read, written, or gated (such as clamping a value or locking
  `PersistentDebugKey` in Release builds), not where it is stored, so direct
  store access, observation, and migration operate on the same entry under `id`.
  Migration does not call these methods, so a custom key gates migration with
  `isMigrationEnabled`.
- **Removing `storeUnavailable` and omitting `LocalizedError`**: A store
  wrapper that cannot migrate throws its own error from `migrationEndpoint`,
  which propagates unchanged instead of being replaced by a generic
  `PersistentKeyMigrationError.storeUnavailable`. Migration errors do not
  conform to `LocalizedError` because they are developer diagnostics and the
  package ships no localized resources (its only bundled resource is
  `PrivacyInfo.xcprivacy`).
- **Suite alias rejection (`/`, `~`, `.plist`, and NUL)**: Core Foundation
  resolves suite names containing `/` (or starting with `~`) as file paths,
  strips a `.plist` suffix in any case, and ends a domain name at its first NUL
  byte (so `base\0a`, `base\0b`, and `base` resolve to the same domain), which
  lets different suite names open the same preferences domain under distinct
  migration identities (or cause `persistentDomain(forName:)` to read the wrong
  domain). `UserDefaults.migratable(suiteName:)` returns `nil` when `suiteName`
  contains `/` or NUL, starts with `~`, or ends with `.plist` (ignoring case),
  checking those delimiters by UTF-8 code units because a combining or
  prepended mark changes the Swift `Character` while Core Foundation still sees
  the ASCII delimiter, and compares domain names using case-folded Swift
  `String` equality (which also folds Unicode canonical equivalence).
- **Literal key identity (and the in-memory and dictionary-value exceptions)**:
  `UserDefaults` and `NSUbiquitousKeyValueStore` store and look up `NSString`
  keys by literal UTF-16 code units, whereas Swift `String` equality merges
  canonically equivalent spellings (such as NFC and NFD spellings of `"café"`).
  The package uses literal UTF-16 key identity (`LiteralKeyID`) across Foundation
  stores: `PersistentKey` and `PersistentDebugKey` `Equatable` and `Hashable`
  conformances compare and hash identifiers by their original UTF-16 code
  units (reading original code units via `NSString` for bridged strings because
  Swift's `String.utf16` reports `U+FFFD` for unpaired surrogates such as one
  left by `NSString.substring(to:)` truncating an emoji, comparing native
  strings by UTF-8 bytes, bridged strings with literal `CFStringCompare`, and
  mixed pairs directly against the Foundation string's UTF-16 buffer when it has
  one and otherwise by copying bounded chunks into temporary storage), so both canonically equivalent spellings and identifiers differing
  only in unpaired surrogates remain distinct set members (whereas SwiftUI
  callers should pass `ForEach(keys, id: \.id.utf8CString)` rather than relying
  on `Identifiable`, whose `id: String` merges canonically equivalent spellings,
  noting that UTF-8 still cannot represent unpaired UTF-16 surrogates so
  identifiers differing only in unpaired surrogates share an ID and `ForEach`
  does not guarantee distinct rows for them, or `\.self`, because synthesized key equality compares identifiers as strings
  and `PersistentKey` and `PersistentDebugKey` equality also compares default
  values so changing only a default recreates the row),
  `UserDefaultsMigrationBackend` sends
  `persistentDomain(forName:)` through Objective-C to keep the unbridged
  `NSDictionary` and looks up keys as `NSString`,
  `PropertyListMigrationStorage.equal` compares strings and
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
  distinguish booleans, integers, and floating-point widths. Snapshots in
  `UserDefaultsMigrationBackend` and `UbiquitousKeyValueMigrationBackend` capture
  `PropertyListMigrationStorage.exactCopy(_:allowingLegacyURL:)` (preserving each
  number's `CFNumber` type, including integer width and `NSDecimalNumber`), so
  migration decodes an exact snapshot of the persisted object, which an
  ordinary `get` can differ from (a launch argument can mask it).
  `PropertyListMigrationStorage.equal(_:_:distinguishingIntegerWidths:)` checks
  `CFBooleanGetTypeID()`, `NSDecimalNumber` (which never compares equal to a
  non-decimal `NSNumber` such as a `Double`, and compares two decimals with
  exact `compare(_:) == .orderedSame`), `CFNumberIsFloatType` (by default, for
  `UserDefaults` and `NSUbiquitousKeyValueStore` migration verification,
  comparing integers by value with `isEqual(to:)` regardless of width because
  `UserDefaults` does not preserve integer width across processes or launches,
  returning an `Int32` as written in the writing process and as `Int64`
  elsewhere; when `distinguishingIntegerWidths` is `true`, comparing integer
  byte sizes with `CFNumberGetByteSize` as well), `CFNumberGetByteSize` (`Float`
  versus `Double`), and `NaN` and floating-point bit patterns (`0.0` versus
  `-0.0`) for both floating-point numbers and `Date` time intervals
  (`timeIntervalSinceReferenceDate`, so an unchanged `NaN` date verifies)
  recursively across arrays and dictionaries, and compares other same-type Core
  Foundation property-list leaves (such as the UIDs in a keyed archive's
  property list, which `InMemoryPersistentKeyValueStore` can hold) by their
  serialized binary property-list data (`otherLeavesEqual`) so in-memory
  migration of keyed archives verifies and detects changed UIDs. Checked
  encoding through `encodeStorageRepresentation` (used by
  `ProxyPersistentKeyValueRepresentationProtocol.encode(_:format:)`,
  `CodablePersistentKeyValueRepresentation.encode(_:format:)`, and migration
  write preparation) first validates the encoded object with
  `isStorablePropertyList(_:)` (a single-walk allow-list accepting strings,
  numbers including Booleans and `NSDecimalNumber`, dates, data, acyclic arrays,
  and string-keyed dictionaries, rejecting keyed-archive UIDs, `NSNull`, `URL`s,
  non-string keys, and self-containing containers itself without relying on
  `PropertyListSerialization.propertyList(_:isValidFor: .binary)`) before
  taking a throwing `PropertyListMigrationStorage.exactCopy(_:allowingLegacyURL:)`
  (throwing `PersistentKeyValueConversionError.encodingFailed` if the object is
  not a storable property list) and validating that immutable Foundation-bridged
  deep copy with `decode(storageObject:format:)`, so a decoder that consumes or
  mutates writable input during validation cannot alter what is returned or
  written. When preparing a write to `UserDefaults` or
  `NSUbiquitousKeyValueStore`, `PropertyListMigrationStorage.storableCopy(of:)`
  captures `exactCopy(object)`, verifies that
  `PropertyListMigrationStorage.equal(copy, try freeze(copy))` holds against a
  binary-property-list-serialized copy, and returns `copy` so the backend commits
  that exact immutable copy, bypassing the key's `set` accessor, throwing
  `PersistentKeyValueConversionError.encodingFailed` at `.prepare` before any
  mutation when binary property-list serialization would change the value or
  stored type (including any `NSDecimalNumber`, even when exact, because binary
  property lists store decimals as `Double`, while allowing integers of any width
  such as `Int32`). `UserDefaultsMigrationBackend`
  removes an existing key before writing when the replacement object is
  `CFEqual` to the snapshot but has a different property-list type so
  `UserDefaults` does not ignore the write, rechecking that the key is still
  absent after removal and failing at `.write` with
  `PersistentKeyMigrationError.destinationChanged` if an observer wrote during
  removal. For `.userDefaults`, `URL.decode(storageObject:format: .userDefaults)`
  reads stored path strings through `NSURL.fileURL(withPath:)` after tilde
  expansion (`(path as NSString).expandingTildeInPath`) so stored paths
  (including tilde-prefixed and relative paths) decode exactly as
  `UserDefaults.url(forKey:)` reads them, and paths that
  `UserDefaults.url(forKey:)` reads as `nil` (such as an empty string or a path
  containing NUL) throw `PersistentKeyValueConversionError.invalidStorageValue`,
  so a migration fails at `.decode` and keeps the source entry. Because
  `UserDefaults` stores file URLs as paths (which strips a
  non-existent directory's trailing slash or drops a file URL host),
  `URL.encode(format: .userDefaults)` verifies that decoding the tilde-abbreviated
  path reproduces `url.absoluteString` and throws
  `PersistentKeyValueConversionError.encodingFailed` when it does not. Checking
  the round-trip in `URL.encode(format:)` rather than on the outer migrated
  value ensures that migration to `UserDefaults` fails at `.prepare` before any
  mutation for direct `URL` keys, `Optional<URL>`, and proxy representations
  over `URL`, and that `UserDefaults.register(_:)` skips such defaults (so typed
  `get(_:)` returns the declared default while raw `url(forKey:)` returns
  `nil` when no other value is visible), while ordinary `UserDefaults` `set`
  keeps Foundation's lossy path behavior and `[URL]` stores `absoluteString`
  values in `.propertyList` format. In `InMemoryPersistentKeyValueStore`,
  snapshots and prepared writes capture an exact immutable copy for Foundation
  property-list objects (such as `NSMutableArray`, including nested
  `NSDecimalNumber` values, including when wrapped in `Optional`) using
  `PropertyListMigrationStorage.exactCopy` (an immutable deep copy that
  preserves exact decimals rather than binary property-list serialization, which
  converts `NSDecimalNumber` to `Double`), the verification snapshot for a
  committed write carries the copy captured when the write was prepared before
  the value was stored and visible to other readers or observers, and
  `migrationSnapshotIsCurrent` compares the current object's contents with
  `PropertyListMigrationStorage.equal(contents, object, distinguishingIntegerWidths: true)`
  (treating integer width as significant recursively because in-memory objects
  remain unserialized) outside
  the lock and then rechecks under the lock that the stored entry still has the
  snapshot's revision (which is never reused); other
  reference types (including references inside Swift values) cannot be copied,
  so snapshots verify them by revision only. Those immutable snapshots (along
  with ordinary write snapshots) are a defense rather than a guarantee of the
  handover contract.
- **Verification releases and post-cleanup checks on `move`**: Migrations release
  replaced destination snapshots, prepared writes, replaced completion marker
  snapshots, and copied or removed source snapshots at their last use before
  verifying the result, so deinitializers run before verification rather than
  masking side effects. Under `.keepDestination` (copy) and `.keepBoth` (move),
  the migration releases the source snapshot and rechecks the kept destination
  at `.write`, failing with `PersistentKeyMigrationError.destinationChanged` (and
  suppressing completion recording) if the destination changed or vanished. On
  `copy`, the source snapshot is released before rechecking the committed
  destination write (`.writeVerificationFailed`). Removing a move's source key
  notifies synchronous observers and releases the source snapshot, which can
  modify either store before `move` returns. Both `.overwriteDestination` and
  `.keepDestinationAndRemoveSource` recheck the destination snapshot after
  removing the source and verifying its removal (failing at `.cleanup` with
  `.destinationChanged` and suppressing completion recording if it changed),
  and then recheck that the source key is still absent (failing at `.cleanup` with
  `PersistentKeyMigrationError.removalVerificationFailed` if the source still
  holds a value, such as when restored by a deinitializer or by the destination
  comparison). Under `.keepDestinationAndRemoveSource`, verifying that the
  preserved destination value has not changed before removing the source runs at
  stage `.write` (reporting `.failed(.write)` with `.destinationChanged` without
  removing the source), because a typed read of the source key cannot
  distinguish a remaining stored value equal to `defaultValue` from a removed
  entry. Consequently, `.failed(.cleanup)` with `.destinationChanged` always
  means the move removed the source and the destination then no longer matched
  its expected snapshot, `.failed(.cleanup)` with `.removalVerificationFailed`
  means the source key still held a value after the removal attempt (without
  rolling back any destination write), and `.failed(.cleanup)` with
  `.sourceChanged` means the source no longer matched its initial snapshot
  before removal so the move did not remove it. On completion recording,
  releasing a replaced marker snapshot before verifying the new marker reports
  `completion == .failed` with `.writeVerificationFailed` if a deinitializer
  changed or removed the marker.
- **Rejection of same-store in-place rewrites**: Same-store in-place rewrites
  (mapping a key to its own identifier with `.key(_:to:transform:)`) were
  designed and implemented during development, then removed before the 2.0.0
  release. Any same-store item whose source and destination key identifiers are
  the same throws `PersistentKeyMigrationError.sameStore` during setup, before
  any key is read, in every store. Retry safety could not be guaranteed for
  in-place rewrites because a tracked batch that fails on a later item replays
  from the start and can read back the old format, the new format, or a widened
  or immutable property-list variant written or read by another process (for
  example, an encoded `Int32` widened to a 64-bit integer that neither or only
  one representation accepts, or an `NSMutableArray` read back as an immutable
  `NSArray`), and each replay guard closed one variant while review found the
  next (including double conversion and an abort on an identity rewrite with a
  consuming decoder). Moving a value to a new key identifier with `move` is
  retry-safe because a successful move removes the source key, so a retry finds
  nothing to convert.
- **Notification-monitored `UserDefaults` keys and observation scope**: Because
  key-value observation parses an identifier by code units as a key path (it
  raises an exception for the empty key and keys containing NUL, treats `.` as
  a key-path component separator even inside a combined character, treats a
  leading `@` as a collection-operator prefix, and calls `NSObject`'s
  `keyPathsForValuesAffectingValueForKey:` without an argument and crashes for
  `valueForKey:` and `ValueForKey:`), `UserDefaults` keys in that set are
  observed through one `UserDefaultsKeyChangeMonitor` associated with each
  `UserDefaults` instance, while all other keys use key-value observation and
  also see other processes' changes (except Foundation posts no KVO notification
  for writes it considers equal to the stored value, such as `Int64` over an
  equal `Int32` or `-0.0` over `0.0`, so a subscriber can keep the previous
  numerically equal value). The monitor installs its
  `UserDefaults.didChangeNotification` observer before the first read,
  reads each registration's own initial comparison value outside the lock and
  stores it under the lock before registration returns (joining an in-progress
  same-thread first read for
  that key, such as from an overridden `object(forKey:)`, instead of calling the
  getter again, and reconciling again if a change arrived during the first
  read; a nested registration of the same key returns before the outer read
  supplies the shared value), and serializes reconciliation with a
  single-drainer loop. Each
  reconciliation pass snapshots the observed keys and the registrations present
  when the pass begins, reads each literal UTF-16 key identifier once, compares
  the read against each registration's comparison value (reusing the previous
  comparison result across registrations that share the same comparison object
  reference, including `NSNumber`, and fast-pathing identical cached
  non-`NSNumber` object references before calling
  `PropertyListMigrationStorage.equal(_:_:distinguishingIntegerWidths: true)`,
  which compares integer widths recursively because `UserDefaults` returns
  in-process writes with their written `CFNumber` width),
  notifies any registration that joined while that reconciliation was in
  progress if any change was reported since it joined (after its first read
  began), even when the value read equals its comparison value (so it may get
  one extra, possibly repeated, emission rather than missing a concurrent write
  that overlapped its initial read), and invokes callbacks outside its lock,
  checking weak observer liveness outside it as well (whereas
  `StoreKeyObservationRegistry` and `InMemoryPersistentKeyValueStore` read weak
  observers under their locks and release the retained observers after
  unlocking). Changes are sampled rather than queued: a
  registration is notified only by reads made after it joined its key, multiple
  changes between two reads produce at most one notification, a change that is
  undone before it is sampled (`A` to `B` to `A`) can produce no notification
  for any subscriber, and consecutive emitted values can be equal. Because
  Foundation posts `didChangeNotification` only for in-process defaults writes
  and not for `addSuite(named:)` or `removeSuite(named:)`, only in-process
  notifications trigger a sample of `object(forKey:)`. A suite-list change or
  cross-process write is not itself a trigger, but the sample rereads the
  effective value, so it can become visible on a later sample. Callbacks under
  concurrent writes can arrive on the reconciling thread.
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
  `Array` and `Dictionary` across built-in representations, failing at `.decode`
  and preserving the source entry instead of silently dropping dictionary
  entries, while representations defined outside the package run their container
  hooks as written.
- **Privacy manifest (`PrivacyInfo.xcprivacy`) reasons**: The library ships
  `PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults`
  with reasons `CA92.1` and `1C8F.1`. Reason `C56D.1` is not declared because
  Apple disallows it for SDKs "created primarily to wrap required reason
  API(s)".
- **Representation handover contract and defensive copies**: An object returned
  from `encode(_:format:)` or `encode(format:)`, returned from a proxy `to`
  conversion, or written through any `set` hook is handed over to the caller
  and must not be mutated afterward (including mutable string or data buffers,
  mutable dictionary keys, or containers); behavior is unspecified otherwise.
  Array hooks may only assign to or append to the empty array passed in, and
  dictionary hooks write only the entry for `dictionaryKey`. Mutating an encoded
  object or earlier dictionary entry during collection conversion could corrupt
  a write or bypass validation, and copying every mutable object on every
  forwarding or key-table path (such as dictionary keys or the forwarding
  container methods of `OptionalPersistentKeyValueRepresentation`,
  `ProxyPersistentKeyValueRepresentation`, and
  `PrimitivePersistentKeyValueRepresentation`) cannot prevent every post-return
  mutation, so the package's immutable snapshots and post-completion dictionary
  validation are defenses rather than guarantees.
- **Reentrant-writer rule**: Verification guards against changes it can
  observe (including changes caused by releasing prepared writes, replaced
  values, and removed values before verification), while code that writes to a
  migrating store as a side effect of reading, encoding, or deallocating a
  value (getters, `deinit`, allocator callbacks, or observers) is an
  uncoordinated writer; coordinate such writers before migrating as with other
  writers, or behavior is unspecified. Side effects inside arbitrary getters,
  codecs, deinitializers, and Core Foundation allocators form an unbounded
  class of reentrant writes that verification cannot exhaustively intercept.
- **Key-identifier contract (`PersistentKeyProtocol.id`) and lock hygiene**: A
  key identifier backed by a Foundation string must not access a store when its
  characters are read, because Foundation may hold its own locks while reading
  a key. Inside the package, `InMemoryPersistentKeyValueStore` ensures
  contiguous UTF-8 storage (`makeContiguousUTF8()` when `!isContiguousUTF8`),
  and `StoreKeyObservationRegistry` and `UserDefaultsKeyChangeMonitor` read
  literal UTF-16 code units (`LiteralKeyID.codeUnits(of:)`) before acquiring
  locks, and removed entries, key groups, observations, and observers are
  released after unlocking so a lazily bridged `NSString` character accessor or
  `deinit` cannot deadlock package locks.
- **Foundation-equal KVO limitation**: `UserDefaults` keys outside the
  key-path-incompatible set continue to use key-value observation even though
  Foundation posts no KVO notification when a write compares equal under
  Foundation equality to the stored value (such as `Int64` over an equal
  `Int32` or `-0.0` over `0.0`). Keeping KVO preserves cross-process observation
  (such as app extensions sharing an app group), which
  `UserDefaults.didChangeNotification` does not deliver because Foundation posts
  it only for in-process defaults writes.
- **In-memory and integer-width rules**: `UserDefaults` and
  `NSUbiquitousKeyValueStore` migration verification compares integers by value
  regardless of width and accepts any integer width during `.prepare`, whereas
  `InMemoryPersistentKeyValueStore` snapshots and `UserDefaultsKeyChangeMonitor`
  compare integer widths recursively (`distinguishingIntegerWidths: true`).
  `UserDefaults` stores integers in property lists by value without preserving
  bit width across processes or launches (returning an `Int32` as written in
  the writing process and a 64-bit integer elsewhere), whereas in-memory objects
  and in-process notification reads remain unserialized `CFNumber` objects
  whose width a representation can observe via `objCType`.
  `InMemoryPersistentKeyValueStore` stores Swift values directly (retaining
  shared references, compacting `nil` only from Swift arrays and `String`-keyed
  dictionaries of optionals, merging canonically equivalent keys, and verifying
  Foundation property-list snapshots by exact copy plus revision while
  verifying other references by revision only).
- **NFC reserved prefix for completion markers**: Migration setup rejects any
  source or destination key identifier whose NFC-normalized UTF-16 code units
  begin with `PersistentKeyValueKit_MigrationCompleted_`
  (`PersistentKeyMigrationError.reservedKey`), including identifiers with a
  combining mark after the underscore or canonically equivalent spellings such
  as `KELVIN SIGN` (`U+212A`) for `K`. Swift's `hasPrefix` compares characters,
  so a combining mark attached to the trailing `_` would hide the prefix, and
  comparing the NFC form's UTF-16 code units also rejects canonically equivalent
  spellings that `InMemoryPersistentKeyValueStore` treats as the same
  dictionary key as a completion marker.

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
  [`MigrationSameKeyTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationSameKeyTests.swift),
  [`MigrationNativeFidelityTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationNativeFidelityTests.swift),
  [`MigrationObservationTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationObservationTests.swift),
  [`MigrationReportTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationReportTests.swift),
  and [`MigrationSetupValidationTests`](../../Tests/PersistentKeyValueKitTests/Tests/Migration/MigrationSetupValidationTests.swift)
  cover same-store and cross-store key mapping, same-key rejection, transforms,
  literal key and property-list type fidelity (including archive UIDs),
  last-use release and post-cleanup rechecks, reentrant-writer scenarios,
  overlap, normalized reserved-prefix, and length validation, report
  invariants, and completion tracking.
- [`PersistentKeyValueRepresentationDefaultsTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key-Value%20Representation/PersistentKeyValueRepresentationDefaultsTests.swift),
  [`StorablePropertyListTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key-Value%20Representation/StorablePropertyListTests.swift),
  [`PrimitiveKeyValuePersistibleDefaultsTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/PrimitiveKeyValuePersistibleDefaultsTests.swift),
  [`CheckedContainerConversionTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/CheckedContainerConversionTests.swift),
  [`CustomContainerHookTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/CustomContainerHookTests.swift),
  [`DictionaryWriteConversionCountTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/DictionaryWriteConversionCountTests.swift),
  [`URLUserDefaultsEncodingTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/Extensions/Foundation/URLUserDefaultsEncodingTests.swift),
  and [`CanonicallyEquivalentKeyTests`](../../Tests/PersistentKeyValueKitTests/Tests/Key-Value%20Persistible/CanonicallyEquivalentKeyTests.swift)
  cover default store and container access built on `decode` and `encode`,
  store property-list allow-list validation and mutable leaf/container snapshots,
  checked container conversion across built-in and custom hooks, single-pass
  ordinary collection writes and first-failure dictionary termination, lossy
  file URL rejection, 1.x appending overrides, and literal versus canonical key
  identity across key equality/hashing, registration, launch arguments, and
  dictionaries.
- [`LiteralKeyIdentityTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key/LiteralKeyIdentityTests.swift),
  [`UnpairedSurrogateKeyTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key/UnpairedSurrogateKeyTests.swift),
  [`InMemoryPersistentKeyValueStoreAccessorTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key-Value%20Store/InMemoryPersistentKeyValueStore/InMemoryPersistentKeyValueStoreAccessorTests.swift),
  [`PersistentKeyValuePublisherTests`](../../Tests/PersistentKeyValueKitTests/Tests/Combine/PersistentKeyValuePublisherTests.swift),
  [`UserDefaultsKeyChangeObservationTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key-Value%20Store/UserDefaults/UserDefaultsKeyChangeObservationTests.swift),
  and [`NSUbiquitousKeyValueStoreObservationTests`](../../Tests/PersistentKeyValueKitTests/Tests/Persistent%20Key-Value%20Store/NSUbiquitousKeyValueStore/NSUbiquitousKeyValueStoreObservationTests.swift)
  cover literal UTF-16 and unpaired-surrogate key identity without copying,
  lock-hygiene identifier conversion and post-unlock release, Combine
  `receive(subscription:)` serialization, the per-instance `UserDefaults`
  notification monitor for key-path-incompatible keys, deduplicated reads,
  registration deregistration races, and literal key matching in observation.
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
