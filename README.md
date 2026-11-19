# PersistentKeyValueKit

[![Platform Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2FPersistentKeyValueKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kylehughes/PersistentKeyValueKit)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2FPersistentKeyValueKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kylehughes/PersistentKeyValueKit)
[![Test](https://github.com/kylehughes/PersistentKeyValueKit/actions/workflows/test.yml/badge.svg)](https://github.com/kylehughes/PersistentKeyValueKit/actions/workflows/test.yml)

*Perfectly-shaped interfaces for `UserDefaults` and `NSUbiquitousKeyValueStore`.*

## About

PersistentKeyValueKit provides a single, type-safe interface for [`UserDefaults`][user-defaults-docs], [`NSUbiquitousKeyValueStore`][ubiquitous-store-docs], and an in-memory store. Define a key once and use it to read, write, remove, bind in SwiftUI, observe from async tasks or Combine, and migrate values between stores without branching on the backing storage engine.

The library is built around three ideas:

- Defining persistence logic once per value type through `KeyValuePersistible`
- Composing custom persistence formats from reusable `PersistentKeyValueRepresentation` building blocks
- Declaring keys centrally with the static accessor pattern

All platform constraints of [`UserDefaults`][user-defaults-docs] and [`NSUbiquitousKeyValueStore`][ubiquitous-store-docs] apply.

[ubiquitous-store-docs]: https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore
[user-defaults-docs]: https://developer.apple.com/documentation/foundation/userdefaults

### Capabilities

- [x] Strongly-typed key-value pairs with explicit default values.
- [x] Persistence for any `Sendable` type conforming to `KeyValuePersistible`.
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

Both built-in key types, `PersistentKey` and `PersistentDebugKey`, require a `Sendable` value type. A `PersistentKey<Value>` pairs a string identifier, which must be unique for each logical key within its store, with a default value and a representation. Defining keys as static members on `PersistentKeyProtocol` enables leading-dot syntax across stores, property wrappers, observation APIs, and migrations:

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

The same key works with `UserDefaults` (`UserDefaults.standard` or `UserDefaults(suiteName:)`), `NSUbiquitousKeyValueStore.default`, and `InMemoryPersistentKeyValueStore`:

```swift
userDefaults.set(.launchCount, to: 1)

if let layoutID = NSUbiquitousKeyValueStore.default.get(.selectedLayoutID(forListID: listID)) {
    applyLayout(id: layoutID)
}
```

Values can also be read by subscript (`store[.launchCount]`) and removed from the persistent domain with `remove(_:)` (reads then return `defaultValue` unless another `UserDefaults` domain, such as launch arguments or registered defaults, supplies a value). Built-in `Bool`, numeric, and `URL` representations coerce `UserDefaults.argumentDomain` strings (a `URL` argument requires a scheme) unless a managed preference overrides the key; optionals and proxies inherit this. `InMemoryPersistentKeyValueStore` keeps Swift values in memory for tests and previews; class instances are shared, so use immutable or `Sendable` reference types across concurrency domains.

#### Define and Access a Debug Key

`PersistentDebugKey<Value>` (whose `Value` must also be `Sendable`) is mutable in Debug builds and locked to its release default in Release builds (`get` returns the release default, `set` and `remove` are no-ops, and migration skips the key with `.keyDisabled`). Custom `PersistentKeyProtocol` types must store values under `id`; migration bypasses their accessors, so use `isMigrationEnabled` to gate it.

> [!WARNING]
> `PersistentDebugKey` uses `#if DEBUG` when compiling `PersistentKeyValueKit` from source; prebuilt Release binaries always take the release path.

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

#### SwiftUI State

`@PersistentValue` reads, writes, and observes a key in a store (defaulting to `defaultPersistentKeyValueStore` in the environment, which defaults to `UserDefaults.standard`), switching when the view updates with a new key or store. A projected `$binding` captures the active key and store when created, keeping only that store alive (not later stores or view state). Use `ForEach(keys, id: \.id.utf8CString)` so canonically equivalent `id` strings stay distinct (identifiers differing only in unpaired UTF-16 surrogates share an ID, and `ForEach` does not guarantee distinct rows for them, so derive row IDs from the original UTF-16 code units; `\.self` is not a substitute because key equality includes `defaultValue`); `PersistentKeyUIObservableObject.value` returns `key.defaultValue` when `store` is `nil`.

```swift
@PersistentValue(.isAppStoreRatingEnabled)
var isAppStoreRatingEnabled: Bool

@PersistentValue(.isAppStoreRatingEnabled, store: .ubiquitous)
var isSyncedRatingEnabled: Bool
```

Use `.defaultPersistentKeyValueStore(_:)` to set the default store for a view hierarchy; an explicit `store:` argument on `@PersistentValue` takes precedence:

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

`PersistentKeyValues` is an `AsyncSequence` that emits values for a key. Entry points are available on both the store and the key, emitting the current value immediately followed by subsequent changes. These loops update a UIKit label, so run them on the main actor, such as from a `@MainActor` function:

```swift
for await username in UserDefaults.standard.values(for: .username) {
    usernameLabel.text = username
}
```

The key form is equivalent; use one or the other, because each loop runs until its task is cancelled:

```swift
let usernameKey: PersistentKey<String> = .username
for await username in usernameKey.values(in: UserDefaults.standard) {
    usernameLabel.text = username
}
```

Use `changes(for:)` or `changes(in:)` to skip the initial value:

```swift
for await username in UserDefaults.standard.changes(for: .username) {
    handleChange(username: username)
}
```

Pending changes default to `.bufferingNewest(1)`. Pass `bufferingPolicy: .unbounded` to buffer every observed value:

```swift
for await username in UserDefaults.standard.changes(for: .username, bufferingPolicy: .unbounded) {
    recordChange(username: username)
}
```

Each change emission reads the latest value from the store (rapid writes can coalesce, and consecutive values can be equal). Iterators deregister on termination or deinitialization, and `next()` returns `nil` and releases buffered values when the task is cancelled while it waits or before it is called.

#### Combine Publishers

`PersistentKeyValuePublisher` is a Combine `Publisher` (`Failure == Never`) that reads the current value on subscription and delivers it on initial demand, followed by subsequent changes. These sinks update a UIKit label, so create them from a `@MainActor` context:

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

Use `changesPublisher(for:)` or `changesPublisher(in:)` to skip the initial value:

```swift
let cancellable = UserDefaults.standard.changesPublisher(for: .username)
    .sink { username in
        handleChange(username: username)
    }
```

Delivery is synchronous and serialized for each subscription. It happens on the thread requesting demand or reporting a change, and a thread already delivering values also delivers changes other threads report, so a setter returning does not mean its update has been delivered. While a subscriber is in `receive(subscription:)`, only the subscribing thread delivers values, so blocking there for another thread's value will hang. Use `.receive(on: DispatchQueue.main)` before updating UI. Exhausted demand coalesces intermediate updates, and subscriptions deregister when cancelled or released.

For `UserDefaults` keys KVO cannot observe (empty keys, keys starting with `@`, keys containing a `.` code unit even in a combined character, keys containing NUL, and `valueForKey:` / `ValueForKey:`), observation uses `UserDefaults.didChangeNotification` instead (in-process defaults notifications request a read of the effective value, and several notifications can share one read of each key, so cross-process and `addSuite(named:)` / `removeSuite(named:)` changes appear only on a later read); other keys use KVO and also see cross-process changes, though Foundation does not post KVO for a write it considers equal to the stored value (such as `Int64` over an equal `Int32` or `-0.0` over `0.0`), so a subscriber can keep the previous, numerically equal value.

### Make a Type Persistible

A type conforms to `KeyValuePersistible` by providing a `PersistentKeyValueRepresentation`:

```swift
public protocol KeyValuePersistible {
    associatedtype PersistentKeyValueRepresentation: PersistentKeyValueKit.PersistentKeyValueRepresentation<Self>

    static var persistentKeyValueRepresentation: Self.PersistentKeyValueRepresentation { get }
}
```

#### Built-In Types

These standard library and Foundation types conform to `KeyValuePersistible`:

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

`Array` and `Dictionary` writes are all-or-nothing, omitting `Optional` `nil` values. For external representations, the default array writer omits an element whose `encode` returns `nil`, and a container hook that leaves a dictionary entry absent (as the default hook does when `encode` returns `nil`), leaves the array empty for non-empty input, or produces objects that stores cannot persist (such as keyed-archive UIDs or cycles; store archives as `Data`) leaves the store unchanged on ordinary writes and throws `.encodingFailed` in checked encoding (used by migration and by `UserDefaults.register(_:)`, which skips a default that fails). Ordinary `Array` reads are all-or-nothing, while ordinary `Dictionary` reads omit undecodable entries. Checked decoding (migration) fails on any undecodable element or entry, except that a custom array reader can return a filtered array; a dictionary entry reader that returns `nil` fails checked decoding.

`URL` supports absolute URLs and relative references. Checked `.userDefaults` decoding reads stored paths like `UserDefaults.url(forKey:)` (throwing `.invalidStorageValue` when it returns `nil`), and checked encoding rejects file URLs whose stored path cannot reproduce the URL (such as a file URL host or a nonexistent directory's trailing slash). Ordinary `set` keeps Foundation's path storage, and `[URL]` stores `absoluteString` values.

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

`CodablePersistentKeyValueRepresentation` encodes and decodes a `Codable` value with a `Sendable` Combine `TopLevelEncoder` and `TopLevelDecoder` whose shared output and input type conforms to `KeyValuePersistible` (defaulting to `JSONEncoder()` and `JSONDecoder()`):

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

`ProxyPersistentKeyValueRepresentation` converts a value to and from another `KeyValuePersistible` proxy type using `to` and `from` closures:

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

Supply `representation:` on `PersistentKey` or `PersistentDebugKey` for a key-specific format (passing a representation for `Unwrapped` directly when the value type is `Optional<Unwrapped>`):

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

Representations convert between Swift values and stored objects (`PersistentKeyValueStorageFormat`: `.propertyList`, `.userDefaults`, or `.ubiquitousKeyValueStore`) through two throwing methods on `PersistentKeyValueRepresentation`:

```swift
func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value
func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any?
```

Returning `nil` from `encode(_:format:)` makes the default `UserDefaults` and `NSUbiquitousKeyValueStore` setters remove the key. The in-memory store does not call representations, and its default setter records an explicitly assigned `nil` for an optional key. Ordinary `get` and `set` remain non-throwing. Conversion can run more than once for the same value. Encoded values and container `set` output must be property lists that stores accept (strings, numbers including Booleans, dates, data, acyclic arrays, and string-keyed dictionaries; store keyed archives as `Data`): proxy and `Codable` `encode(_:format:)` throw `PersistentKeyValueConversionError.encodingFailed` for unsupported encodings such as keyed-archive UIDs, and default `set` methods leave the store unchanged.

An object returned from `encode`, returned from a proxy `to`, or written by any `set` method is handed over and must not be mutated afterward (including mutable strings, data buffers, dictionary keys, or containers); behavior is unspecified otherwise. Array `set(_:to:)` hooks may only assign or append to the empty array passed in, and dictionary `set(_:to:in:)` hooks must write only the entry for the given key. Proxy representations (`ProxyPersistentKeyValueRepresentation` and `ProxyPersistentKeyValueRepresentationProtocol`) derive `decode` and `encode` from `from(_:)` and `to(_:)`, and direct `PersistentKeyValueRepresentation` or `PrimitiveKeyValuePersistible` conformers inherit default store and container methods, which checked conversion calls as written for external representations (see the [2.0.0 Release Notes](docs/release-notes/2.0.0.md)).

### Migrate Values Between Stores

Use `copy` or `move` (taking a key, a `PersistentKeyMigrationItem`, `[any PersistentKeyProtocol]`, or `items: [PersistentKeyMigrationItem]`) to transfer persisted values between stores or rename and transform keys within a store. Every call requires `onConflict:` and `tracking:`, and returns a `PersistentKeyMigrationReport`. Sharing preferences requires the same App Group on each target (substitute its identifier for `group.example.app`), and iCloud sync requires the Key-value storage service:

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

#### Rename and Transform Keys

Pass `PersistentKeyMigrationItem` values when keys change name or value type (`.key(_:)`, `.key(_:to:)` for same-type renames, or `.key(_:to:transform:)` for throwing `@Sendable` value transforms):

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

Same-store migrations are allowed when every item maps its source key to a different destination key (no duplicate or overlapping keys); in-place rewrites are not supported, and any same-store item whose source and destination key identifiers are the same throws `PersistentKeyMigrationError.sameStore` at setup before any key is read. To change a key's stored representation or value format, migrate it to a new key ID with `move` (if a batch runs again after a `move` removed its source, that item reports `.sourceAbsent`; if the source remains, the keep policies keep an earlier attempt's write without running `transform`, and `.overwriteDestination` replaces it, running `transform` again).

`transform` runs in input order after source decoding, when both keys are enabled (`isMigrationEnabled == true`) and the conflict policy selects a write (a later failure can still prevent the write); if it throws, the item fails at `.transform` and writes to neither store. An `InMemoryPersistentKeyValueStore` source passes stored Swift values without running representation codecs, so copy a mutable reference input in `transform` before mutating it.

#### Conflict Policies and Partial Changes

| Operation | Conflict policy | Existing destination value |
| --- | --- | --- |
| Copy | `.keepDestination` | Verify destination unchanged, then keep destination and source values (`.keptDestination`). |
| Copy | `.overwriteDestination` | Replace destination and keep source (`.copied`). |
| Move | `.keepBoth` | Verify destination unchanged, then keep destination and source values (`.keptDestination`). |
| Move | `.overwriteDestination` | Replace destination, then remove source (`.moved`). |
| Move | `.keepDestinationAndRemoveSource` | Verify destination unchanged, then remove source (`.discardedSource`). |

`.keepBoth` on a `move` leaves conflicting source values in place; use `.keepDestinationAndRemoveSource` or `.overwriteDestination` to remove conflicting source entries. The keep policies compare the stored destination without decoding it, so `.keepDestinationAndRemoveSource` can discard the only readable value when the key cannot decode the destination. An overwrite stores the object the destination key's representation encodes, and a `nil` encoding removes the destination entry (as the built-in optional representation does for `nil`), so a move can then leave neither key. Only values persisted in each store's own domain participate (registered defaults, launch arguments, added suites, and `defaultValue` are ignored).

Setup errors (`PersistentKeyMigrationError`) throw before any item runs, as does an error reading a tracked batch's completion marker (an undecodable marker throws `.invalidCompletionRecord`); per-item failures go into `report.outcomes` (`.failed(FailureStage)` with `outcome.error`) as remaining items continue. Foundation writes fail at `.prepare` with `.encodingFailed` when the encoded object cannot persist as is (such as keyed-archive UIDs, or an `NSDecimalNumber`, which serialization stores as a `Double`) or, for an iCloud destination, with `.invalidStorageValue` when its binary property list exceeds 1 MiB; iCloud also limits the store to 1 MB in total and 1,024 keys, including a completion marker recorded there. Preparation verifies that the object decodes and that serialization preserves it, but a custom representation determines how much of the original Swift value survives (the ISO 8601 date above stores whole seconds). At `.write`, a changed expected destination produces `.destinationChanged`, and a committed value that fails verification produces `.writeVerificationFailed`. Migrations do not roll back completed writes: at `.cleanup`, `.sourceChanged` means the move skipped removal, `.destinationChanged` means the destination differed after the source was removed, and `.removalVerificationFailed` means the source still held a value after removal; another writer may have changed either key. Coordinate other writers, processes, and reentrant callbacks (getters, `deinit`, allocators, observers) before migrating, or behavior is unspecified. Local completion does not guarantee disk durability or iCloud delivery, and removing an iCloud key deletes it across devices.

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

try report.throwIfIncomplete()
```

#### Completion Tracking

`PersistentKeyMigrationTracking` provides `.untracked` (`report.completion` is `.untracked`), `.once(id:)` (recorded in the destination store), and `.once(id:recordedIn:)`. With `.once`, `.isMigrationCompleted(id:)` is recorded once every item resolves without failure (`.recorded`), including skipped items, so a batch that transferred nothing is still recorded, and later calls skip the batch (`.alreadyRecorded`); if any item fails, `report.completion` is `.notRecorded`, and if recording or verifying the marker fails, `report.completion` is `.failed` with `report.completionError`. A retry reads the stored marker again, so a marker that was written but failed verification can still be honored. Any item or marker failure leaves `report.isComplete == false`, causing `try report.throwIfIncomplete()` to throw `PersistentKeyMigrationIncompleteError`. Until a `.once` marker is recorded, retrying re-runs the batch under its conflict policy; remove `.isMigrationCompleted(id:)` (or set it to `false`) to reset tracking, or pick a new `id` when changing a migration.

A marker recorded in `NSUbiquitousKeyValueStore` syncs across devices; pass `.once(id:recordedIn: UserDefaults.standard)` to run a local-to-iCloud migration once per device instead. When migrating *from* `NSUbiquitousKeyValueStore`, a `.once` migration before initial sync sees missing keys as `.sourceAbsent` and records completion; use `.untracked` until initial sync completes or record completion yourself. Conflict checks against an iCloud destination likewise read this device's local cache, so to preserve existing cloud preferences, wait for the current account's initial data before seeding; migration does not wait for sync.

#### Named `UserDefaults` Suites

Any named `UserDefaults` suite a migration reads, writes, or uses for `recordedIn:` must be created with `UserDefaults.migratable(suiteName:)`, returning the native `UserDefaults` instance with process-local domain metadata attached for its lifetime (`nil` for empty, NUL-containing, path-shaped, `.plist`-suffixed, or reserved domain names). `UserDefaults.standard` (requiring a non-empty `Bundle.main.bundleIdentifier`, or throwing `.missingApplicationIdentifier`), `NSUbiquitousKeyValueStore.default`, and `InMemoryPersistentKeyValueStore` need no special setup, and ordinary `UserDefaults(suiteName:)` instances work outside migrations. See the [2.0.0 Release Notes](docs/release-notes/2.0.0.md) and the [native-store migration decision record](docs/decisions/2026-09-15-native-store-migration.md) for validation and verification details.

### `UserDefaults` Registration

Register key default values in the `UserDefaults` registration domain with `register(_:)` when sharing `UserDefaults` with code that reads raw `UserDefaults` APIs:

```swift
userDefaults.register(.launchCount)
```

`register(_:)` encodes each key's `defaultValue` using `.userDefaults` format (skipping defaults that fail checked `.userDefaults` encoding, such as lossy file `URL`s, for which typed `get(_:)` still returns `defaultValue` while raw `url(forKey:)` returns `nil` when no other value is visible).

## Important Behavior Differences

### No Implicit Defaults

Raw `UserDefaults` and `NSUbiquitousKeyValueStore` getters such as `bool(forKey:)` and `integer(forKey:)` return `false` or `0` when a key is unset. `PersistentKeyValueKit` requires an explicit `defaultValue` on every key and distinguishes missing values from stored `false` or `0`. Use an `Optional` value type with `defaultValue: nil` when `nil` should mean there is no readable non-`nil` value: a missing, unreadable, or (in memory) explicitly `nil` entry all read as `nil`, while a stored `false` or `0` does not:

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

`PersistentKeyValueKit` provides `KeyValuePersistible` conformances for homogeneous collections:

| Supported (`KeyValuePersistible`) | Not supported |
| --- | --- |
| `[Element] where Element: KeyValuePersistible` | `[any KeyValuePersistible]` |
| `[String: Value] where Value: KeyValuePersistible` | `[String: any KeyValuePersistible]` |

For structured heterogeneous data, use `CodablePersistentKeyValueRepresentation` or implement `PrimitiveKeyValuePersistible`.

### `NSUbiquitousKeyValueStore` Observation Scope

Foundation posts `NSUbiquitousKeyValueStore.didChangeExternallyNotification` for changes arriving from iCloud and for events such as quota violations, not for local writes. `PersistentKeyValueKit` therefore posts `NSUbiquitousKeyValueStore.didChangeInternallyNotification` on the writing `NSUbiquitousKeyValueStore` instance after each store-level `set(_:to:)` or `remove(_:)`, even when the key ignores the operation and leaves storage unchanged (such as a Release `PersistentDebugKey`); a key's own `set(to:in:)` and `remove(from:)` post nothing, so use the store methods for local writes that observers must see. Migrations post it for the keys they write or remove. Observation sees remote iCloud updates and those in-app changes on that instance (use `NSUbiquitousKeyValueStore.default` everywhere, as Apple requires), and refreshes all observed keys on account-change or keyless external notifications.

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
