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
- [x] Typed copy and move migrations between stores with conflict policies and optional completion tracking.
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

#### Define and Access a Debug Key

`PersistentDebugKey<Value>` is mutable in Debug builds and fixed to its release default value in Release builds. In Release builds, `get` always returns the release default, and `set` and `remove` are no-ops. Both `PersistentKey` and `PersistentDebugKey` conform to `PersistentKeyProtocol`.

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
userDefaults.get(.isAppStoreRatingEnabled) // false in Debug, true in Release
```

### Make a Type Persistible

A type conforms to `KeyValuePersistible` by providing a `PersistentKeyValueRepresentation`:

```swift
public protocol KeyValuePersistible {
    associatedtype PersistentKeyValueRepresentation: PersistentKeyValueKit.PersistentKeyValueRepresentation<Self>

    static var persistentKeyValueRepresentation: Self.PersistentKeyValueRepresentation { get }
}
```

A representation defines how a Swift value is converted to and from a store's underlying storage format.

#### Primitive Types

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

Other types persist by converting to one of these primitive types—or to another `KeyValuePersistible` type—through a representation.

### Persistence Representations

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

Conversion can throw (`PersistentKeyValueConversionError` for built-in representations, or the underlying coder error for `CodablePersistentKeyValueRepresentation`). Returning `nil` from `encode(_:format:)` removes the key from the store (or omits the element from a property-list collection). Ordinary `get` and `set` operations remain non-throwing.

Proxy representations (`ProxyPersistentKeyValueRepresentation` and types conforming to `ProxyPersistentKeyValueRepresentationProtocol`) implement `decode(storageObject:format:)` and `encode(_:format:)` automatically using their `from` and `to` conversions. In 2.0.0, types that conform directly to `PersistentKeyValueRepresentation` must implement `decode(storageObject:format:)` and `encode(_:format:)`, and custom `PrimitiveKeyValuePersistible` types must implement `static func decode(storageObject:format:)` and `func encode(format:)`.

### Observation

PersistentKeyValueKit provides three ways to observe a key in a store: `@PersistentValue` for SwiftUI views, `PersistentKeyValues` as an `AsyncSequence`, and `PersistentKeyValuePublisher` for Combine.

#### SwiftUI State

`@PersistentValue` reads and writes a key in a `PersistentKeyValueStore` and invalidates the view when the key's value changes in that store.

If no store is passed to `@PersistentValue`, it reads `defaultPersistentKeyValueStore` from the SwiftUI environment, which defaults to `UserDefaults.standard`.

```swift
@PersistentValue(.isAppStoreRatingEnabled)
var isAppStoreRatingEnabled: Bool

@PersistentValue(.isAppStoreRatingEnabled, store: .ubiquitous)
var isSyncedRatingEnabled: Bool
```

Use `.defaultPersistentKeyValueStore(_:)` to set the default store for a view hierarchy. An explicit `store:` argument on `@PersistentValue` still takes precedence over the environment store.

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

`PersistentKeyValues` is an `AsyncSequence` that emits values for a single key. You can create the same sequence from the store or from the key:

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

Pending changes use `.bufferingNewest(1)` by default, so a slow consumer receives the latest pending value rather than an unbounded backlog. Pass `bufferingPolicy: .unbounded` to buffer every observed change:

```swift
for await username in UserDefaults.standard.changes(for: .username, bufferingPolicy: .unbounded) {
    recordChange(username: username)
}
```

Each iterator registers an observer with the store and deregisters when iteration terminates, the iterator is deinitialized, or the enclosing `Task` is cancelled.

#### Combine Publishers

`PersistentKeyValuePublisher` is a Combine `Publisher` (`Failure == Never`) for a single key. Equivalent entry points are available on both the store and the key:

```swift
let cancellable = UserDefaults.standard.publisher(for: .username)
    .sink { username in
        usernameLabel.text = username
    }

let usernameKey: PersistentKey<String> = .username
let keyCancellable = usernameKey.publisher(in: UserDefaults.standard)
    .sink { username in
        usernameLabel.text = username
    }
```

By default, `publisher(for:)` and `publisher(in:)` emit the current value when initial demand is requested, followed by subsequent changes. Use `changesPublisher(for:)` or `changesPublisher(in:)` to skip the initial value:

```swift
let cancellable = UserDefaults.standard.changesPublisher(for: .username)
    .sink { username in
        handleChange(username: username)
    }
```

If downstream demand is exhausted when changes arrive, intermediate updates are coalesced so the next demand request receives the latest current value. Each subscription registers with the store and deregisters when cancelled or released.

### Migrate Values Between Stores

Use `copy` or `move` on any migration-capable `PersistentKeyValueStore` to transfer values between stores using your existing typed keys. A batch (`[any PersistentKeyProtocol]`) can contain keys with different value types:

```swift
guard let destination = UserDefaults.migratable(suiteName: "group.example.app") else {
    return
}

let report = try UserDefaults.standard.copy(
    [.runtimeColorScheme, .launchCount],
    to: destination,
    onConflict: .overwriteDestination
)
```

Named `UserDefaults` suites must be created with `UserDefaults.migratable(suiteName:)` to participate in migration. It returns an ordinary `UserDefaults` instance with attached process-local domain metadata, or `nil` if creation fails or the suite name is invalid (empty, reserved, or matching the application bundle identifier). Ordinary `UserDefaults(suiteName:)` instances without migration metadata cannot be migrated and throw `PersistentKeyMigrationError.missingMigrationDomain`.

`UserDefaults.standard` supports migration when `Bundle.main.bundleIdentifier` is available. `NSUbiquitousKeyValueStore.default` and `InMemoryPersistentKeyValueStore` require no migration-specific setup.

Every `copy` and `move` call requires a conflict policy specifying what happens when the destination store already contains a persisted value for a key:

| Operation | Conflict policy | Existing destination value |
| --- | --- | --- |
| Copy | `.keepDestination` | Preserve the destination value and leave the source value in place. |
| Copy | `.overwriteDestination` | Replace the destination value and leave the source value in place. |
| Move | `.keepBoth` | Preserve both the destination value and the source value. |
| Move | `.overwriteDestination` | Replace the destination value, then remove the source value. |
| Move | `.keepDestinationAndRemoveSource` | Preserve the destination value and remove the source value. |

Only values persisted in a store's own domain participate in migration. Registered defaults (`UserDefaults.register`), launch arguments (`UserDefaults.argumentDomain`), added suites (`UserDefaults.addSuite(named:)`), and a key's `defaultValue` are not migrated from the source and do not count as destination conflicts. Each value is decoded from the source and encoded for the destination using its key's representation.

Setup errors—such as missing domain metadata, migrating a store to itself, duplicate key IDs, reserved completion-marker keys, or overlapping in-process migrations on the same key—are thrown before any key is modified. Per-key failures appear in `report.outcomes`, and the batch continues with the remaining keys.

Migrations do not roll back completed work: if a `move` writes the destination value and removing the source value fails, the copied value remains in the destination. Coordinate other writers and processes before migrating. Local completion does not guarantee disk durability or iCloud delivery, and removing a key from `NSUbiquitousKeyValueStore` removes it across the user's devices.

#### Track a Migration

Pass `completion: .once(id:recordedIn:)` to record a persistent completion marker after the batch finishes:

```swift
let report = try UserDefaults.standard.move(
    [.runtimeColorScheme],
    to: destination,
    onConflict: .keepBoth,
    completion: .once(id: "app-group-preferences-v1", recordedIn: destination)
)

if !report.isComplete {
    // Inspect report.outcomes and report.completion before retrying.
}
```

Completion is recorded when every key in the batch finishes without failure. Missing source values (`.sourceAbsent`), disabled keys (`.keyDisabled`), and conflicts resolved by policy (`.keptDestination`, `.discardedSource`) do not prevent completion. If any key fails, the marker is not written (`report.completion` is `.notRecorded`).

Once recorded, later calls with the same `id` and recording store skip the migration and return an empty `outcomes` array with `completion: .alreadyRecorded`. Until recording succeeds, retrying runs the batch again under its conflict policy; tracking is a persistent marker, not an in-flight transaction or an exactly-once guarantee.

Remove `.isMigrationCompleted(id:)` from the recording store to reset tracking. Use a new identifier when changing the keys or behavior of a migration.

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

Foundation posts `NSUbiquitousKeyValueStore.didChangeExternallyNotification` only for changes received from iCloud, not for changes written locally in the current process. To make local and remote updates behave consistently, `PersistentKeyValueKit` posts `NSUbiquitousKeyValueStore.didChangeInternallyNotification` whenever a value is written or removed through `PersistentKeyValueStore`, `@PersistentValue`, or store migration.

As a result, `@PersistentValue`, `PersistentKeyValues`, and `PersistentKeyValuePublisher` observe remote iCloud changes and in-app changes made through `PersistentKeyValueKit`, but do not observe local writes made directly to `NSUbiquitousKeyValueStore` outside the package.

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
