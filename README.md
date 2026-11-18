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

A `PersistentKey<Value>` pairs a string key identifier with a value type, a default value, and a representation. Defining keys as static members on `PersistentKeyProtocol` enables leading-dot syntax across stores, property wrappers, observation APIs, and migrations:

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

Values can also be read by subscript (`store[.launchCount]`) and removed from the store's persistent domain with `remove(_:)` (subsequent reads fall back to `defaultValue` unless another `UserDefaults` search-list domain, such as launch arguments or registered defaults, supplies a value). Built-in representations coerce string values from `UserDefaults.argumentDomain` unless a managed preference overrides the key. `InMemoryPersistentKeyValueStore` keeps Swift values in memory for tests and previews; class instances are shared, so use immutable or `Sendable` reference types across concurrency domains.

#### Define and Access a Debug Key

`PersistentDebugKey<Value>` is mutable in Debug builds and locked to its release default in Release builds (`get` returns the release default, `set` and `remove` are no-ops, and migration skips the key with `.keyDisabled`). Custom `PersistentKeyProtocol` types must store values under `id`.

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

`@PersistentValue` reads, writes, and observes a key in a store (defaulting to `defaultPersistentKeyValueStore` in the environment, which defaults to `UserDefaults.standard`), switching when the view updates with a new key or store. A projected `$binding` captures the key and store active when created, keeping only that store alive (not later stores or view state).

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

`PersistentKeyValues` is an `AsyncSequence` that emits values for a key. Entry points are available on both the store and the key, emitting the current value immediately followed by subsequent changes:

```swift
for await username in UserDefaults.standard.values(for: .username) {
    usernameLabel.text = username
}

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

Each change emission reads the latest value from the store (rapid writes can coalesce, and consecutive values can be equal). Iterators deregister on termination, deinitialization, or task cancellation (which immediately returns `nil` and releases buffered values).

#### Combine Publishers

`PersistentKeyValuePublisher` is a Combine `Publisher` (`Failure == Never`) that reads the current value on subscription and delivers it on initial demand, followed by subsequent changes:

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

Values are delivered synchronously on the thread that requests demand or reports a store change (or on the thread already delivering when a concurrent update arrives, so a setter returning does not mean its update has been delivered yet); use `.receive(on: DispatchQueue.main)` before updating UI. Exhausted demand coalesces intermediate updates, and subscriptions deregister when cancelled or released.

For `UserDefaults` keys containing `.`, observation uses `UserDefaults.didChangeNotification` instead of key-value observation and delivers only in-process property-list changes (not cross-process writes or `addSuite(named:)` / `removeSuite(named:)`).

### Make a Type Persistible

A type conforms to `KeyValuePersistible` by providing a `PersistentKeyValueRepresentation`:

```swift
public protocol KeyValuePersistible {
    associatedtype PersistentKeyValueRepresentation: PersistentKeyValueKit.PersistentKeyValueRepresentation<Self>

    static var persistentKeyValueRepresentation: Self.PersistentKeyValueRepresentation { get }
}
```

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

`Array` and `Dictionary` writes are all-or-nothing (omitting `Optional` `nil` values). Ordinary `Array` reads are all-or-nothing, whereas ordinary `Dictionary` reads omit undecodable entries; checked conversion (migration and `UserDefaults.register(_:)`) fails if any element or entry cannot be decoded (unless a custom representation's container hook omits it). `URL` supports absolute and relative URLs; checked `.userDefaults` encoding rejects file URLs whose stored path cannot reproduce the URL (such as a file URL host or nonexistent directory trailing slash, including through `Optional` and proxies), while ordinary `set` keeps Foundation's path storage and `[URL]` stores `absoluteString` values.

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

`CodablePersistentKeyValueRepresentation` encodes and decodes a `Codable` value using a Combine `TopLevelEncoder` and `TopLevelDecoder` whose output type conforms to `KeyValuePersistible` (defaulting to `JSONEncoder()` and `JSONDecoder()`):

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

Returning `nil` from `encode(_:format:)` removes the key from a store; ordinary `get` and `set` remain non-throwing. Proxy representations (`ProxyPersistentKeyValueRepresentation` and `ProxyPersistentKeyValueRepresentationProtocol`) implement `decode` and `encode` from `from(_:)` and `to(_:)`, and direct `PersistentKeyValueRepresentation` or `PrimitiveKeyValuePersistible` conformers inherit default store and container `get` and `set` methods (for external representations, checked conversion calls their container methods as written, and a dictionary entry or non-empty array that encodes entirely to `nil` fails the write; see the [2.0.0 Release Notes](docs/release-notes/2.0.0.md)).

### Migrate Values Between Stores

Use `copy` or `move` (taking a key, a `PersistentKeyMigrationItem`, `[any PersistentKeyProtocol]`, or `items: [PersistentKeyMigrationItem]`) to transfer persisted values between stores or rename and transform keys in place. Every call requires `onConflict:` and `tracking:`, and returns a `PersistentKeyMigrationReport`:

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

Same-store migrations are allowed when every item maps its source key to a different destination key (with no duplicate or overlapping source/destination keys) or, in `UserDefaults` or `NSUbiquitousKeyValueStore`, rewrites a key in place with `.key(_:to:transform:)` (`InMemoryPersistentKeyValueStore` does not support in-place rewrites and throws `.sameStore` during setup). Within a single `UserDefaults` or `NSUbiquitousKeyValueStore` instance, `.key(source, to: destination, transform:)` with the same key identifier rewrites the stored value in place and reports `.rewritten` under any conflict policy (pass `transform: { $0 }` to upgrade only a key's representation). Before writing, a rewrite decodes its prepared result with the source key and, if that decodes, runs `transform` and encodes once more, failing at `.prepare` with `PersistentKeyMigrationError.nonIdempotentRewrite` unless the result either fails the source key's decoder (such as `Int` to `String`) or reproduces the same encoded value (requiring reproducible encoding, such as `JSONEncoder` with `.sortedKeys`, when the source key can still decode the result). For overlapping formats such as `Int` to `Double` (seconds to milliseconds) or dollars to cents, move the value to a new key identifier instead.

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

`transform` runs when both keys are enabled (`isMigrationEnabled == true`) and the item will write to the destination; if its initial call throws, the item fails at `.transform` without modifying either store (whereas a failure during rewrite verification fails at `.prepare` with `.nonIdempotentRewrite`). Migrations between `InMemoryPersistentKeyValueStore` instances transfer Swift values directly without running representation codecs.

#### Conflict Policies and Partial Changes

| Operation | Conflict policy | Existing destination value |
| --- | --- | --- |
| Copy | `.keepDestination` | Preserve the destination value and leave the source value in place (`.keptDestination`). |
| Copy | `.overwriteDestination` | Replace the destination value and leave the source value in place (`.copied`). |
| Move | `.keepBoth` | Preserve both the destination value and the source value (`.keptDestination`). |
| Move | `.overwriteDestination` | Replace the destination value, then remove the source value (`.moved`). |
| Move | `.keepDestinationAndRemoveSource` | Preserve the destination value and remove the source value (`.discardedSource`). |

`.keepBoth` on a `move` leaves conflicting source values in place; use `.keepDestinationAndRemoveSource` or `.overwriteDestination` when conflicting source entries must be removed. Only values persisted in each store's own domain participate (registered defaults, launch arguments, added suites, and `defaultValue` are ignored).

Setup errors (`PersistentKeyMigrationError`) are thrown before any key is accessed. Once the batch begins, per-item failures are recorded in `report.outcomes` (`.failed(FailureStage)` at `.snapshot`, `.decode`, `.transform`, `.prepare`, `.write`, or `.cleanup`, with `outcome.error`) while remaining items continue. Migrations do not roll back completed work, and a `move` that fails at `.cleanup` does not roll back its destination write (`.sourceChanged` at `.cleanup` means the source no longer matched its snapshot before removal, so the move did not remove it; `.destinationChanged` at `.cleanup` means the move removed the source and the destination then no longer matched its expected snapshot; other writers or observers may have modified or removed either store's value). Coordinate other writers and processes before migrating; local completion does not guarantee disk durability or iCloud delivery, and removing a key from `NSUbiquitousKeyValueStore` removes it across the user's devices.

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

#### Completion Tracking

`PersistentKeyMigrationTracking` offers `.untracked` (`report.completion` is always `.untracked`), `.once(id:)` (recording `.isMigrationCompleted(id:)` in the destination store), and `.once(id:recordedIn:)`. With `.once`, completion is recorded when every item resolves without failure (`.recorded`), and later calls skip the batch and return `.alreadyRecorded`; if any item fails, `report.completion` is `.notRecorded`, and if writing or verifying the marker fails after all items succeed, `report.completion` is `.failed` with `report.completionError`. In all tracking modes, any item or marker failure leaves `report.isComplete == false`, and `try report.throwIfIncomplete()` throws `PersistentKeyMigrationIncompleteError`. Until a `.once` marker is recorded, retrying runs the batch again (including items that already completed) under its conflict policy. Remove `.isMigrationCompleted(id:)` (or set it to `false`) to reset tracking, or choose a new `id` when changing a migration.

A marker recorded in `NSUbiquitousKeyValueStore` syncs across devices; pass `.once(id:recordedIn: UserDefaults.standard)` to run a local-to-iCloud migration once per device instead. When migrating *from* `NSUbiquitousKeyValueStore`, a `.once` migration that runs before initial sync sees missing keys as `.sourceAbsent` and permanently records completion; use `.untracked` until initial sync has completed or record completion under your app's own control.

#### Named `UserDefaults` Suites

Any named `UserDefaults` suite that a migration reads, writes, or uses for `recordedIn:` must be created with `UserDefaults.migratable(suiteName:)`, which returns the native `UserDefaults` instance with process-local domain metadata attached for its lifetime (`nil` for empty, path-shaped, `.plist`-suffixed, or reserved domain names). `UserDefaults.standard` (requiring a non-empty `Bundle.main.bundleIdentifier`, or throwing `.missingApplicationIdentifier`), `NSUbiquitousKeyValueStore.default`, and `InMemoryPersistentKeyValueStore` need no special setup, and ordinary `UserDefaults(suiteName:)` instances continue to work outside migrations. See the [2.0.0 Release Notes](docs/release-notes/2.0.0.md) and the [native-store migration decision record](docs/decisions/2026-09-15-native-store-migration.md) for validation and verification details.

### `UserDefaults` Registration

Register key default values in the `UserDefaults` registration domain with `register(_:)` when sharing `UserDefaults` with code that reads raw `UserDefaults` APIs:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 1)
    }
}

userDefaults.register(.launchCount)
```

`register(_:)` encodes each key's `defaultValue` using `.userDefaults` format (skipping defaults that fail checked `.userDefaults` encoding, such as lossy file `URL`s, for which typed `get(_:)` still returns `defaultValue` while raw `url(forKey:)` returns `nil` when no other value is visible).

## Important Behavior Differences

### No Implicit Defaults

Raw `UserDefaults` and `NSUbiquitousKeyValueStore` getters such as `bool(forKey:)` and `integer(forKey:)` return `false` or `0` when a key is unset. `PersistentKeyValueKit` requires an explicit `defaultValue` on every key and distinguishes missing values from stored `false` or `0`. Use an `Optional` value type with `defaultValue: nil` to distinguish an unset key from a stored value:

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

Foundation posts `NSUbiquitousKeyValueStore.didChangeExternallyNotification` only for changes received from iCloud, so `PersistentKeyValueKit` posts `NSUbiquitousKeyValueStore.didChangeInternallyNotification` on the writing `NSUbiquitousKeyValueStore` instance whenever a value is written or removed through the package. Observation therefore sees remote iCloud updates and in-app changes made through `PersistentKeyValueKit` on that same instance (use `NSUbiquitousKeyValueStore.default` everywhere, as Apple requires), and refreshes all observed keys on account-change or keyless external notifications.

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
