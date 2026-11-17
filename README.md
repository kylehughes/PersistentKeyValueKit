# PersistentKeyValueKit

[![Platform Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2FPersistentKeyValueKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kylehughes/PersistentKeyValueKit)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2FPersistentKeyValueKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kylehughes/PersistentKeyValueKit)
[![Test](https://github.com/kylehughes/PersistentKeyValueKit/actions/workflows/test.yml/badge.svg)](https://github.com/kylehughes/PersistentKeyValueKit/actions/workflows/test.yml)

*Perfectly-shaped interfaces for `UserDefaults` and `NSUbiquitousKeyValueStore`.*

## About

PersistentKeyValueKit provides a single, type-safe interface for [`UserDefaults`][user-defaults-docs], [`NSUbiquitousKeyValueStore`][ubiquitous-store-docs], and an in-memory store. You define a key once and use it to read, write, remove, bind in SwiftUI, observe from async tasks or Combine, and migrate values between stores without branching on the backing storage engine.

The library is built around three ideas:

- Defining persistence logic once per value type through `KeyValuePersistible`
- Composing custom persistence formats from reusable `PersistentKeyValueRepresentation` building blocks
- Declaring keys centrally with the static accessor pattern

All platform constraints of [`UserDefaults`][user-defaults-docs] and [`NSUbiquitousKeyValueStore`][ubiquitous-store-docs] apply.

[ubiquitous-store-docs]: https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore
[user-defaults-docs]: https://developer.apple.com/documentation/foundation/userdefaults

### Capabilities

- [x] Strongly-typed key-value pairs with explicit default values.
- [x] Persistence for any type conforming to `KeyValuePersistible`.
- [x] Shared `PersistentKeyValueStore` interface for `UserDefaults`, `NSUbiquitousKeyValueStore`, and `InMemoryPersistentKeyValueStore`.
- [x] SwiftUI `@PersistentValue` property wrapper and environment store modifier.
- [x] `AsyncSequence` and Combine publishers for observing key changes.
- [x] Built-in support for property-list primitive types and homogeneous collections.
- [x] Built-in representations for `RawRepresentable`, `Codable`, `LosslessStringConvertible`, and custom proxy types.
- [x] Typed copy and move migrations between or within stores with key mapping, value transforms, conflict policies, and completion tracking.
- [x] Debug-only mutable keys via `PersistentDebugKey`.
- [x] Swift 6 language mode support.

## Supported Platforms

- iOS 15.0+
- macOS 13.0+
- tvOS 15.0+
- visionOS 1.0+
- watchOS 8.0+ (`NSUbiquitousKeyValueStore` APIs require watchOS 9.0+)

## Requirements

- Swift 6.2+
- Xcode 26.0+

## Documentation

- [API Documentation](https://kylehughes.github.io/PersistentKeyValueKit)
- [2.0.0 Release Notes](docs/release-notes/2.0.0.md)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/kylehughes/PersistentKeyValueKit.git", .upToNextMajor(from: "2.0.0")),
]
```

The `PersistentKeyValueKit` target bundles an Apple privacy manifest (`PrivacyInfo.xcprivacy`) declaring `UserDefaults` access (`NSPrivacyAccessedAPICategoryUserDefaults`) with reasons `CA92.1` and `1C8F.1`.

## Quick Start

Conform your type to `KeyValuePersistible`:

```swift
import PersistentKeyValueKit

enum RuntimeColorScheme: String {
    case dark
    case light
    case system
}

extension RuntimeColorScheme: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}
```

Define a typed key using the static accessor pattern:

```swift
import PersistentKeyValueKit

extension PersistentKeyProtocol where Self == PersistentKey<RuntimeColorScheme> {
    static var runtimeColorScheme: Self {
        Self("RuntimeColorScheme", defaultValue: .system)
    }
}
```

Bind the key in a SwiftUI view:

```swift
import PersistentKeyValueKit
import SwiftUI

struct SettingsView: View {
    @PersistentValue(.runtimeColorScheme)
    var runtimeColorScheme

    var body: some View {
        Picker("Appearance", selection: $runtimeColorScheme) {
            Text("System").tag(RuntimeColorScheme.system)
            Text("Light").tag(RuntimeColorScheme.light)
            Text("Dark").tag(RuntimeColorScheme.dark)
        }
    }
}
```

Read and write the key from any store:

```swift
let currentScheme = userDefaults.get(.runtimeColorScheme)
userDefaults.set(.runtimeColorScheme, to: .dark)
```

Observe changes from async code:

```swift
for await runtimeColorScheme in userDefaults.values(for: .runtimeColorScheme) {
    apply(runtimeColorScheme)
}
```

Observe changes with Combine:

```swift
let cancellable = userDefaults.publisher(for: .runtimeColorScheme)
    .receive(on: DispatchQueue.main)
    .sink { runtimeColorScheme in
        apply(runtimeColorScheme)
    }
```

## Usage

### Keys

#### Define and Access a Key

A `PersistentKey<Value>` pairs a string key identifier with a value type, a default value, and a representation. Defining keys as static members on `PersistentKeyProtocol` lets call sites use leading-dot syntax across stores, property wrappers, observation APIs, and migrations:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 0)
    }
}
```

Keys with dynamic identifiers can be defined as static functions:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<String?> {
    static func selectedLayoutID(forListID listID: String) -> Self {
        Self("\(listID)::SelectedLayoutID", defaultValue: nil)
    }
}
```

The same key works with `UserDefaults` (such as `UserDefaults.standard` or `UserDefaults(suiteName:)`), `NSUbiquitousKeyValueStore.default`, and `InMemoryPersistentKeyValueStore`:

```swift
userDefaults.set(.launchCount, to: 1)

if let layoutID = NSUbiquitousKeyValueStore.default.get(.selectedLayoutID(forListID: listID)) {
    applyLayout(id: layoutID)
}
```

You can also read values with subscript syntax (`store[.launchCount]`). Use `remove(_:)` to delete the value stored in the target store's persistent domain; subsequent reads fall back to the key's `defaultValue` unless another `UserDefaults` search-list domain (such as launch arguments or registered defaults) supplies a value. Built-in representations coerce string values from `UserDefaults.argumentDomain` into typed values only when the literal key's launch argument is the visible value and the key is not managed (`!objectIsForced(forKey:)`), so managed preferences take precedence per Apple's search order.

`InMemoryPersistentKeyValueStore` stores and returns the Swift value itself, compacting `nil` elements only out of Swift arrays and `String`-keyed dictionaries of optionals whose compacted result still has the value's type (leaving Foundation collections such as `NSMutableArray` unchanged). Because class-typed values are shared rather than copied, use immutable or `Sendable` reference types when accessing an in-memory store across concurrency domains.

#### Define and Access a Debug Key

`PersistentDebugKey<Value>` is mutable in Debug builds and locked to its release default value in Release builds across `UserDefaults`, `NSUbiquitousKeyValueStore`, and `InMemoryPersistentKeyValueStore`, where `get` always returns the release default, `set` and `remove` are no-ops, and store migrations check `isMigrationEnabled` and skip the key with `.keyDisabled`. Both `PersistentKey` and `PersistentDebugKey` conform to `PersistentKeyProtocol`. A key's value always lives under its `id` in every store; custom `PersistentKeyProtocol` implementations can customize how a value is read, written, or gated, while observation and migration access the entry under `id`.

> [!WARNING]
> `PersistentDebugKey` relies on the `#if DEBUG` compilation condition when compiling `PersistentKeyValueKit` from source (such as through Swift Package Manager). Prebuilt binary distributions compiled in Release mode will always take the release path.

```swift
extension PersistentKeyProtocol where Self == PersistentDebugKey<Bool> {
    static var isAppStoreRatingEnabled: Self {
        Self(
            "IsAppStoreRatingEnabled",
            debugDefaultValue: false,
            releaseDefaultValue: true
        )
    }
}

userDefaults.set(.isAppStoreRatingEnabled, to: false)
let isRatingEnabled = userDefaults.get(.isAppStoreRatingEnabled) // false in Debug, true in Release
```

### Observation

PersistentKeyValueKit provides three ways to observe a key in a store: `@PersistentValue` for SwiftUI views, `PersistentKeyValues` as an `AsyncSequence`, and `PersistentKeyValuePublisher` for Combine.

#### SwiftUI State

`@PersistentValue` reads and writes a key in a `PersistentKeyValueStore` and invalidates the view when the key's value changes in that store. When a view updates at the same identity with a different key, a different explicit `store:`, or a new `defaultPersistentKeyValueStore` in the environment, `@PersistentValue` switches to reading, writing, and observing the new key and store (comparing key identifiers by literal UTF-16 code units). A `$binding` projected from `@PersistentValue` captures the key and store active when the binding was created, so a retained binding continues reading and writing its original key and store after the view switches.

If no store is passed to `@PersistentValue`, it reads `defaultPersistentKeyValueStore` from the SwiftUI environment, which defaults to `UserDefaults.standard`.

```swift
@PersistentValue(.isAppStoreRatingEnabled)
var isAppStoreRatingEnabled: Bool

@PersistentValue(.isAppStoreRatingEnabled, store: .ubiquitous)
var isSyncedRatingEnabled: Bool
```

Use `.defaultPersistentKeyValueStore(_:)` to set the default store for a view hierarchy. An explicit `store:` argument on `@PersistentValue` takes precedence over the environment store.

```swift
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .defaultPersistentKeyValueStore(.ubiquitous)
        }
    }
}
```

#### Async Sequences

`PersistentKeyValues` is an `AsyncSequence` that emits values for a single key. Equivalent entry points are available on both the store and the key:

```swift
for await username in UserDefaults.standard.values(for: .username) {
    usernameLabel.text = username
}

let usernameKey: PersistentKey<String> = .username
for await username in usernameKey.values(in: UserDefaults.standard) {
    usernameLabel.text = username
}
```

By default, `values(for:)` and `values(in:)` emit the current value immediately when iteration begins, followed by subsequent changes. Use `changes(for:)` or `changes(in:)` to skip the initial value and receive only subsequent changes:

```swift
for await username in UserDefaults.standard.changes(for: .username) {
    handleChange(username: username)
}
```

Pending changes use `.bufferingNewest(1)` by default, so a slow consumer receives the latest observed value rather than an unbounded backlog. Pass `bufferingPolicy: .unbounded` to buffer every observed value:

```swift
for await username in UserDefaults.standard.changes(for: .username, bufferingPolicy: .unbounded) {
    recordChange(username: username)
}
```

Each element after the initial value is the current state read from the store after a change is reported, emitted in read order and never older than an element already emitted. Changes reported during registration before the initial value is read are not re-emitted out of order, rapid writes can coalesce into a single read, and consecutive elements can be equal. Each iterator registers with the store and deregisters when iteration terminates, the iterator is deinitialized, or the iterating `Task` is cancelled. If the task is cancelled before or during `next()`, `next()` deregisters and returns `nil` without returning a pending initial or buffered value, and subsequent calls on that iterator also return `nil`.

#### Combine Publishers

`PersistentKeyValuePublisher` is a Combine `Publisher` (`Failure == Never`) for a single key. Equivalent entry points are available on both the store and the key:

```swift
let cancellable = UserDefaults.standard.publisher(for: .username)
    .receive(on: DispatchQueue.main)
    .sink { username in
        usernameLabel.text = username
    }

let usernameKey: PersistentKey<String> = .username
let keyCancellable = usernameKey.publisher(in: UserDefaults.standard)
    .receive(on: DispatchQueue.main)
    .sink { username in
        usernameLabel.text = username
    }
```

By default, `publisher(for:)` and `publisher(in:)` read the current value when the publisher receives its subscriber and deliver it when initial demand is first requested, followed by subsequent changes. Use `changesPublisher(for:)` or `changesPublisher(in:)` to skip the initial value:

```swift
let cancellable = UserDefaults.standard.changesPublisher(for: .username)
    .sink { username in
        handleChange(username: username)
    }
```

The publisher delivers values synchronously on the thread that requests demand or reports a store change (or on the thread currently delivering values when changes arrive concurrently), so use `.receive(on: DispatchQueue.main)` before updating UI. Values are read outside the subscription's lock and delivered serially in read order; if a subscription is cancelled while a value is being read, that value is not delivered. If downstream demand is exhausted when changes arrive, intermediate updates are coalesced so the next demand request receives the latest current value. Each subscription registers with the store and deregisters when cancelled or released.

For `UserDefaults`, keys without `.` use key-value observation. Because key-value observation treats `.` as a key-path separator, keys whose identifiers contain `.` are observed through a shared per-instance `UserDefaults.didChangeNotification` monitor across `@PersistentValue`, `PersistentKeyValues`, `PersistentKeyValuePublisher`, and `UserDefaults.register(observer:for:with:and:)`. The monitor deduplicates reads per key and notifies observers when the key's property-list value changes; under concurrent writes, callbacks can arrive on the thread currently reconciling changes. Foundation posts `UserDefaults.didChangeNotification` only for changes made in the current process and not for `addSuite(named:)` or `removeSuite(named:)`, so cross-process changes and suite-list changes are not delivered for dotted keys.

### Make a Type Persistible

A type conforms to `KeyValuePersistible` by providing a `PersistentKeyValueRepresentation`:

```swift
public protocol KeyValuePersistible {
    associatedtype PersistentKeyValueRepresentation: PersistentKeyValueKit.PersistentKeyValueRepresentation<Self>

    static var persistentKeyValueRepresentation: Self.PersistentKeyValueRepresentation { get }
}
```

A representation defines how a Swift value is converted to and from a store's underlying storage format.

#### Built-In Types

The following standard library and Foundation types conform to `KeyValuePersistible` out of the box:

- `Array<Element> where Element: KeyValuePersistible`
- `Bool`
- `Data`
- `Dictionary<String, Value> where Value: KeyValuePersistible`
- `Double`
- `Float`
- `Int`
- `Optional<Wrapped> where Wrapped: KeyValuePersistible`
- `String`
- `URL`

Other types persist by converting to one of these built-in types or to another `KeyValuePersistible` type through a representation.

`Array` and `Dictionary` writes are all-or-nothing: if any element or entry fails to encode, the store or enclosing property-list container is left unchanged, while `Optional` `nil` elements and entries are omitted. On ordinary reads, `Array` is also all-or-nothing (returning the key's `defaultValue` if any element fails to decode), whereas `Dictionary` keeps readable entries and omits undecodable ones so one unrecognized entry (such as an enum case written by a newer app version) does not blank the whole dictionary; if a stored Foundation dictionary contains canonically equivalent keys with different Unicode encodings, bridging to a Swift dictionary keeps one entry. Checked conversion (`decode(storageObject:format:)` and `encode(_:format:)`, used by store migration and `UserDefaults.register(_:)`) routes through the element or value representation's property-list container hooks so custom container formats round-trip, and fails if any element or entry cannot be decoded or if a stored dictionary's keys would collapse into one Swift key. `URL` supports absolute URLs and relative URL references; when migrating to `UserDefaults`, file URLs whose path encoding cannot reproduce their `absoluteString` (such as a non-existent directory's trailing slash or a file URL host) fail at `.prepare` before any store is modified.

#### `RawRepresentablePersistentKeyValueRepresentation`

`RawRepresentablePersistentKeyValueRepresentation` persists a `RawRepresentable` type as its `RawValue` when `RawValue` conforms to `KeyValuePersistible`:

```swift
enum NotificationFrequency: String {
    case daily
    case weekly
    case monthly
}

extension NotificationFrequency: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}
```

#### `CodablePersistentKeyValueRepresentation`

`CodablePersistentKeyValueRepresentation` encodes and decodes a `Codable` value using a Combine `TopLevelEncoder` and `TopLevelDecoder` whose output type conforms to `KeyValuePersistible` (such as `Data` with `JSONEncoder` and `JSONDecoder`).

```swift
struct Contact: Codable, Sendable {
    let nickname: String
    let dateOfBirth: Date
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension Contact: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        CodablePersistentKeyValueRepresentation()
    }
}
```

The zero-argument initializer uses `JSONEncoder()` and `JSONDecoder()`. Pass custom coders to `init(encoder:decoder:)`.

#### `LosslessStringConvertiblePersistentKeyValueRepresentation`

`LosslessStringConvertiblePersistentKeyValueRepresentation` persists a `LosslessStringConvertible` value as a `String`:

```swift
extension Character: @retroactive KeyValuePersistible {
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        LosslessStringConvertiblePersistentKeyValueRepresentation()
    }
}
```

#### `ProxyPersistentKeyValueRepresentation`

`ProxyPersistentKeyValueRepresentation` converts a value to and from another `KeyValuePersistible` proxy type using `to` and `from` closures. Proxy types can be chained to any depth.

For example, `Date` can be persisted as a `TimeInterval` (`Double`):

```swift
extension Date: @retroactive KeyValuePersistible {
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        ProxyPersistentKeyValueRepresentation(
            to: \.timeIntervalSinceReferenceDate,
            from: { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }
}
```

#### Custom Representation for a Single Key

You can supply an explicit representation when defining a `PersistentKey` or `PersistentDebugKey`, even if the value type does not conform to `KeyValuePersistible` or needs a key-specific format. When the key's value type is `Optional<Unwrapped>`, you can pass a representation for `Unwrapped` directly:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Date?> {
    static var mostRecentAppStoreReviewRequestDate: Self {
        Self(
            "MostRecentAppStoreReviewRequestDate",
            defaultValue: nil,
            representation: ProxyPersistentKeyValueRepresentation(
                to: { (date: Date) in date.ISO8601Format() },
                from: { string in try? Date.ISO8601FormatStyle().parse(string) }
            )
        )
    }
}
```

#### Implement a Representation

Representations convert between Swift values and stored objects through two throwing methods on `PersistentKeyValueRepresentation`:

```swift
func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value
func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any?
```

`PersistentKeyValueStorageFormat` identifies the target storage format: `.propertyList` (nested arrays and dictionaries), `.userDefaults`, or `.ubiquitousKeyValueStore`.

Conversion can throw (`PersistentKeyValueConversionError` for built-in representations, or the underlying coder error for `CodablePersistentKeyValueRepresentation`). Returning `nil` from `encode(_:format:)` removes the key from the store (or omits the element from a property-list collection). Ordinary `get` and `set` calls remain non-throwing.

Proxy representations (`ProxyPersistentKeyValueRepresentation` and types conforming to `ProxyPersistentKeyValueRepresentationProtocol`) implement `decode(storageObject:format:)` and `encode(_:format:)` automatically using their `from(_:)` and `to(_:)` conversions. Types that conform directly to `PersistentKeyValueRepresentation` implement `decode(storageObject:format:)` and `encode(_:format:)`, and custom `PrimitiveKeyValuePersistible` types implement `static func decode(storageObject:format:)` and `func encode(format:)`. The eight store- and container-specific `get` and `set` methods have default implementations built on these two methods: default reads return `nil` on absence or decode failure, default writes remove the key when `encode` returns `nil` and leave the store or container unchanged when `encode` throws or returns a non-property-list object, and default `UserDefaults` reads do not coerce `UserDefaults.argumentDomain` launch-argument strings. Custom `set(_:to: inout [Any])` and `set(_:to:in: inout [String: Any])` overrides receive an empty array or a dictionary without the target key and may either assign or append; leaving the array empty for non-empty input (or leaving the dictionary key absent) counts as a failure unless every element (or the entry's value) encodes to `nil`.

### Migrate Values Between Stores

Use `copy` or `move` on any migration-capable `PersistentKeyValueStore` to transfer persisted values between stores or rename and transform keys in place. Every call requires an explicit conflict policy (`onConflict:`) and completion-tracking mode (`tracking:`), and returns a `PersistentKeyMigrationReport`:

```swift
func makeAppGroupDefaults() throws -> UserDefaults? {
    guard let appGroup = UserDefaults.migratable(suiteName: "group.example.app") else {
        return nil
    }

    let report = try UserDefaults.standard.move(
        [.runtimeColorScheme, .launchCount],
        to: appGroup,
        onConflict: .keepBoth,
        tracking: .once(id: "app-group-preferences-v1")
    )
    try report.throwIfIncomplete()

    return appGroup
}
```

`copy` and `move` accept a single key, a single `PersistentKeyMigrationItem`, an unlabeled array of keys (`[any PersistentKeyProtocol]`), or a labeled `items:` array (`[PersistentKeyMigrationItem]`).

#### Rename and Transform Keys

Pass `PersistentKeyMigrationItem` values to `copy(_:to:onConflict:tracking:)`, `move(_:to:onConflict:tracking:)`, `copy(items:to:onConflict:tracking:)`, or `move(items:to:onConflict:tracking:)` when keys change name or value type:

- `.key(_:)` migrates a key to the same key in the destination store.
- `.key(_:to:)` migrates a source key to a different destination key of the same `Value` type, decoding with the source key's representation and encoding with the destination key's representation.
- `.key(_:to:transform:)` converts the decoded source value with a throwing `@Sendable` closure before encoding for the destination key.

```swift
let report = try UserDefaults.standard.move(
    items: [
        .key(.legacyLaunchCount, to: .launchCount),
        .key(
            .legacyDarkModeEnabled,
            to: .runtimeColorScheme,
            transform: { isDarkModeEnabled in
                isDarkModeEnabled ? .dark : .light
            }
        ),
    ],
    to: appGroup,
    onConflict: .keepBoth,
    tracking: .once(id: "app-group-preferences-v2")
)
try report.throwIfIncomplete()
```

The source and destination can be the same store when every item in the batch either maps its source key to a different destination key or rewrites the key in place with `.key(_:to:transform:)`. Duplicate source or destination key identifiers in a batch throw `PersistentKeyMigrationError.duplicateKey(_:)`, and same-store batches where one item's destination is another item's source (such as `A` to `B` and `B` to `C`, or `A` to `B` and `B` to `A`) throw `PersistentKeyMigrationError.overlappingKeys(_:)` so results never depend on item order. Key identity follows the store: `UserDefaults` and `NSUbiquitousKeyValueStore` compare identifiers by literal UTF-16 code units (treating NFC and NFD spellings as distinct keys), whereas `InMemoryPersistentKeyValueStore` is keyed by Swift `String` and treats canonically equivalent identifiers as one key.

Within a single store instance, `.key(source, to: destination, transform:)` where `source` and `destination` have byte-identical key identifiers (`source.id.utf8.elementsEqual(destination.id.utf8)`) rewrites the stored value in place: it decodes with `source`'s representation, converts the value with `transform`, encodes the result with `destination`'s representation, replaces the stored value only if its snapshot has not changed, verifies the write, never removes the key as a source during a `move`, and reports `.rewritten` under every copy or move conflict policy. Pass `transform: { $0 }` when upgrading only a key's representation under the same identifier. If a tracked batch is retried after a later item fails, a stored value that fails to decode with `source`'s representation but decodes with `destination`'s is treated as already rewritten and reports `.rewritten` without running `transform` or writing again. An in-place rewrite must therefore change the stored representation or use an idempotent `transform`; to change a value without changing its stored format (such as converting dollars to cents), move it to a new key identifier instead. `.key(_:)` and `.key(_:to:)`, or a rewrite between two distinct instances for one backing store, throw `PersistentKeyMigrationError.sameStore`. Rewrites still participate in duplicate-key and overlap checks.

```swift
let legacyColorSchemeKey = PersistentKey<Int>("RuntimeColorScheme", defaultValue: 0)

let report = try userDefaults.move(
    .key(
        legacyColorSchemeKey,
        to: .runtimeColorScheme,
        transform: { rawScheme in
            rawScheme == 1 ? .dark : .light
        }
    ),
    to: userDefaults,
    onConflict: .overwriteDestination,
    tracking: .once(id: "runtime-color-scheme-v2")
)
try report.throwIfIncomplete()
```

An item's `transform` runs after the source value decodes, when both keys have `isMigrationEnabled == true` and the item will write to the destination (for an in-place rewrite, when the destination key has no persisted value, or when `onConflict` is `.overwriteDestination`). It does not run when the source key has no persisted value (`.sourceAbsent`) or when a conflict policy keeps an existing destination value (`.keptDestination` or `.discardedSource`). If `transform` throws, the item fails at stage `.transform` with the thrown error in `outcome.error`, and neither store is modified for that item, leaving the source value in place even during a `move`.

Because `InMemoryPersistentKeyValueStore` stores Swift values directly without encoding or decoding them through `PersistentKeyValueRepresentation`, migrations between in-memory stores transfer the stored value by type cast and do not run representation codecs. Use a `UserDefaults` suite (via `UserDefaults.migratable(suiteName:)`) or `NSUbiquitousKeyValueStore` when testing representation conversion in a migration.

#### Conflict Policies and Partial Changes

Every `copy` and `move` call specifies what happens when the destination store already has a persisted value for an item's destination key:

| Operation | Conflict policy | Existing destination value |
| --- | --- | --- |
| Copy | `.keepDestination` | Preserve the destination value and leave the source value in place (`.keptDestination`). |
| Copy | `.overwriteDestination` | Replace the destination value and leave the source value in place (`.copied`). |
| Move | `.keepBoth` | Preserve both the destination value and the source value (`.keptDestination`). |
| Move | `.overwriteDestination` | Replace the destination value, then remove the source value (`.moved`). |
| Move | `.keepDestinationAndRemoveSource` | Preserve the destination value and remove the source value (`.discardedSource`). |

`.keepBoth` on a `move` (like both `copy` policies) leaves conflicting source values in the source store after the migration completes. Use `.keepDestinationAndRemoveSource` or `.overwriteDestination` when a move must remove conflicting source entries. Conflict policies do not apply to an in-place rewrite within one store, because the existing value is the source being rewritten.

Only values persisted in a store's own domain participate in migration. Registered defaults (`UserDefaults.register`), launch arguments (`UserDefaults.argumentDomain`), added suites (`UserDefaults.addSuite(named:)`), and a key's `defaultValue` are not migrated from the source and do not count as destination conflicts. `UserDefaults` migration snapshots read the writable domain as an unbridged `NSDictionary` so keys are matched by literal UTF-16 code units. Snapshot verification compares property-list types and floating-point widths (`Float` versus `Double`) as well as values recursively, so boolean `true` and integer `1` are not treated as equal; in-memory snapshots compare the contents of Foundation property-list objects and verify other reference types by revision.

Setup errors (`PersistentKeyMigrationError`, such as missing domain metadata, migrating a key to itself within one store without a transform, rewriting between two distinct instances of one store, duplicate or overlapping key IDs, reserved completion-marker keys, key identifiers exceeding `NSUbiquitousKeyValueStore`'s 128-UTF-16-code-unit limit, an empty migration identifier, or an overlapping in-process migration on the same key) are thrown before any key in the batch is read or modified.

Once the batch begins, items are processed in input order and per-item failures are recorded in `report.outcomes` (with `.failed(FailureStage)` at `.snapshot`, `.decode`, `.transform`, `.prepare`, `.write`, or `.cleanup`, and the underlying error in `outcome.error`) while the remaining items continue. Migrations do not roll back completed work: earlier items that succeeded remain committed, and if a `move` writes the destination value and then fails during `.cleanup` while removing the source value, the written value remains in the destination store. A `move` that fails at `.cleanup` with `PersistentKeyMigrationError.destinationChanged` detected a destination change either before removing the source (when `.keepDestinationAndRemoveSource` saw the kept destination change and left the source in place) or after removing the source (for example, when a source-key observer modified the destination); read the source key to tell whether it was removed. A `UserDefaults` write or rewrite that replaces a stored value with a `CFEqual` value of a different property-list type removes the old object first and fails at `.write` with `.destinationChanged` if an observer writes the key during removal. Call `try report.throwIfIncomplete()` to throw `PersistentKeyMigrationIncompleteError` (which carries `report`) when any item or completion marker fails or goes unrecorded, or inspect `report.outcome(for:)` directly by passing the item's source key (matched by literal UTF-16 code units):

```swift
let report = try UserDefaults.standard.copy(
    [.runtimeColorScheme, .launchCount],
    to: .ubiquitous,
    onConflict: .keepDestination,
    tracking: .once(id: "icloud-initial-seed-v1", recordedIn: UserDefaults.standard)
)

if let outcome = report.outcome(for: .runtimeColorScheme), let error = outcome.error {
    handleMigrationError(error, at: outcome.status)
}
```

Coordinate other writers and processes before migrating. Local completion does not guarantee disk durability or iCloud delivery, and removing a key from `NSUbiquitousKeyValueStore` removes it across the user's devices.

#### Completion Tracking

`PersistentKeyMigrationTracking` controls whether a migration records a persistent completion marker:

- `.untracked` runs the batch on every call and reports `completion: .untracked`.
- `.once(id:)` checks and records the marker `.isMigrationCompleted(id:)` in the migration's destination store.
- `.once(id:recordedIn:)` checks and records the marker `.isMigrationCompleted(id:)` in the specified store.

Completion is recorded when every item in the batch resolves without failure (including `.rewritten`, `.sourceAbsent`, `.keyDisabled`, `.keptDestination`, `.discardedSource`, or an empty batch `[]`). If any item fails, the marker is not written (`report.completion` is `.notRecorded`). If writing or verifying the marker itself fails, `report.completion` is `.failed` and `report.completionError` holds the error.

Once recorded, later calls with the same `id` and recording store skip the migration without reading or mutating any keys in the batch and return an empty `outcomes` array with `completion: .alreadyRecorded`. `PersistentKeyMigrationReport`'s public fixture initializers enforce with preconditions that `outcomes` is empty for `.alreadyRecorded`, contains at least one failed outcome for `.notRecorded`, and contains no failed outcomes for `.recorded` or `.failed` (`init(outcomes:completionError:)`). Until recording succeeds, retrying runs the batch again under its conflict policy.

Each completion marker is stored under `"PersistentKeyValueKit_MigrationCompleted_"` (containing no `.` characters) followed by the unpadded base64url-encoded SHA-256 digest of `id` normalized to Unicode Normalization Form C (NFC), producing an 84-UTF-16-code-unit key that `UserDefaults` key-value observation can observe directly and that fits within `NSUbiquitousKeyValueStore`'s 128-UTF-16-code-unit key limit for any `id`. Migration identifiers that compare equal as Swift strings share one marker, while identifiers that differ by case remain distinct. Remove `.isMigrationCompleted(id:)` from the recording store (or set it to `false`) to reset tracking, or choose a new `id` when changing a migration's keys or behavior.

When the completion marker is recorded in `NSUbiquitousKeyValueStore` (for example, migrating to `.ubiquitous` with `.once(id:)`), iCloud syncs the marker like any other value. Devices that receive the marker before running the migration report `.alreadyRecorded` and skip the batch, while a device that runs before the marker arrives still performs the migration under its conflict policy. To run a local-to-iCloud migration once per device instead, record the marker in a local `UserDefaults` store using `.once(id:recordedIn: UserDefaults.standard)`. When migrating *from* `NSUbiquitousKeyValueStore`, incoming iCloud data may not have arrived in the local cache yet; a `.once` migration that runs before initial sync sees missing keys as `.sourceAbsent`, records completion, and skips later calls even after the remote values arrive. Run cloud-to-local migrations with `.untracked` until the app knows initial sync has completed, or record completion under the app's own control.

#### Named `UserDefaults` Suites

Any named `UserDefaults` suite that a migration reads or writes (as the receiver or `to:` destination of `copy` or `move`, or as the store passed to `.once(id:recordedIn:)`) must be created with `UserDefaults.migratable(suiteName:)`. `UserDefaults.standard` does not need `migratable(suiteName:)` and supports migration automatically when `Bundle.main.bundleIdentifier` is available (`NSUbiquitousKeyValueStore.default` and `InMemoryPersistentKeyValueStore` also require no migration-specific setup). Other code in your app can continue using `UserDefaults(suiteName:)` for ordinary `get`, `set`, `remove`, `@PersistentValue`, and observation, or share the instance returned by `UserDefaults.migratable(suiteName:)`, which is the same native `UserDefaults` object with process-local domain metadata attached for its lifetime.

`UserDefaults.migratable(suiteName:)` returns `nil` if `suiteName` is empty, contains `/`, begins with `~`, ends with `.plist` (in any case), matches (ignoring case and Unicode normalization) `UserDefaults.argumentDomain`, `UserDefaults.registrationDomain`, `UserDefaults.globalDomain`, `kCFPreferencesAnyApplication`, `kCFPreferencesCurrentApplication`, or `Bundle.main.bundleIdentifier`, or cannot be created by Foundation, because path-shaped and `.plist`-suffixed names can alias the same preferences file as another suite name. Using an ordinary non-standard `UserDefaults(suiteName:)` instance in a migration throws `PersistentKeyMigrationError.missingMigrationDomain` before any key is accessed. Migration compares `UserDefaults` domain names ignoring case and Unicode normalization, treating suite names that differ only by case or normalization as the same store.

### `UserDefaults` Registration

You can register key default values in the `UserDefaults` registration domain with `register(_:)`:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 1)
    }
}

userDefaults.register(.launchCount)
```

`register(_:)` preserves literal key identifiers (keeping canonically equivalent NFC and NFD spellings separate) and encodes each key's `defaultValue` using `.userDefaults` format (the same representation used when writing to `UserDefaults`), so registered defaults for types with `UserDefaults`-specific encodings such as web `URL`s read back identically through both typed `get(_:)` and raw `UserDefaults.url(forKey:)`.

> [!NOTE]
> Registration is unnecessary when all reads go through `PersistentKeyValueKit`, which returns each key's `defaultValue` when no value is stored. Registering defaults is useful when sharing a `UserDefaults` instance with code or frameworks that read keys through raw `UserDefaults` APIs.

## Important Behavior Differences

### No Implicit Defaults

Raw `UserDefaults` and `NSUbiquitousKeyValueStore` getters such as `bool(forKey:)` and `integer(forKey:)` return `false` or `0` when a key is unset, making an unset key indistinguishable from a stored `false` or `0`.

`PersistentKeyValueKit` requires an explicit `defaultValue` on every key and distinguishes missing values from stored values (including `false` and `0`). Use an `Optional` value type with `defaultValue: nil` when you need to distinguish an unset key from a stored value:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Bool?> {
    static var arePushNotificationsEnabled: Self {
        Self("ArePushNotificationsEnabled", defaultValue: nil)
    }
}
```

When a non-optional default is sufficient, use a non-optional value type:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Bool> {
    static var arePushNotificationsEnabled: Self {
        Self("ArePushNotificationsEnabled", defaultValue: true)
    }
}
```

### No Heterogeneous Collections

`UserDefaults` and `NSUbiquitousKeyValueStore` accept untyped `[Any]` arrays and `[String: Any]` dictionaries, whereas `PersistentKeyValueKit` provides `KeyValuePersistible` conformances for homogeneous collections:

| Supported (`KeyValuePersistible`) | Not supported |
| --- | --- |
| `[Element] where Element: KeyValuePersistible` | `[any KeyValuePersistible]` |
| `[String: Value] where Value: KeyValuePersistible` | `[String: any KeyValuePersistible]` |

For structured heterogeneous data, conform a struct or enum to `Codable` and use `CodablePersistentKeyValueRepresentation`, or implement `PrimitiveKeyValuePersistible` directly for custom `[String: Any]` dictionary storage.

### `NSUbiquitousKeyValueStore` Observation Scope

Foundation posts `NSUbiquitousKeyValueStore.didChangeExternallyNotification` only for changes received from iCloud, not for changes written locally in the current process. To make local and remote updates behave consistently, `PersistentKeyValueKit` posts `NSUbiquitousKeyValueStore.didChangeInternallyNotification` with the writing `NSUbiquitousKeyValueStore` instance as the notification object whenever a value is written or removed through `PersistentKeyValueStore`, `@PersistentValue`, or store migration.

As a result, `@PersistentValue`, `PersistentKeyValues`, and `PersistentKeyValuePublisher` observe remote iCloud changes and in-app changes made through `PersistentKeyValueKit` on that same `NSUbiquitousKeyValueStore` instance, but do not observe local writes made directly to `NSUbiquitousKeyValueStore` outside the package; use `NSUbiquitousKeyValueStore.default` everywhere, as Apple requires. External notifications that report an iCloud account change (`NSUbiquitousKeyValueStoreAccountChange`) or omit `NSUbiquitousKeyValueStoreChangedKeysKey` refresh all observed keys. Direct `NSUbiquitousKeyValueStore.register(observer:for:with:and:)` and `deregister(_:for:context:)` calls track registrations per observer, literal key identifier, and context and invoke `selector` only for notifications that may affect that key.

## Contributions

PersistentKeyValueKit is not accepting source contributions at this time. Bug reports will be considered.

## Author

[Kyle Hughes](https://kylehugh.es)

[![Bluesky][bluesky_image]][bluesky_url]  
[![LinkedIn][linkedin_image]][linkedin_url]  
[![Mastodon][mastodon_image]][mastodon_url]

[bluesky_image]: https://img.shields.io/badge/Bluesky-0285FF?logo=bluesky&logoColor=fff
[bluesky_url]: https://bsky.app/profile/kylehugh.es
[linkedin_image]: https://img.shields.io/badge/LinkedIn-0A66C2?logo=linkedin&logoColor=fff
[linkedin_url]: https://www.linkedin.com/in/kyle-hughes
[mastodon_image]: https://img.shields.io/mastodon/follow/109356914477272810?domain=https%3A%2F%2Fmister.computer&style=social
[mastodon_url]: https://mister.computer/@kyle

## Resources

- Apple: [Designing for Key-Value Data in iCloud](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForKey-ValueDataIniCloud.html)
- Apple: [Preferences and Settings Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/Introduction/Introduction.html#//apple_ref/doc/uid/10000059i)

## License

PersistentKeyValueKit is available under the MIT license.

See `LICENSE` for details.
