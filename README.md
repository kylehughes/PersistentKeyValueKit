# PersistentKeyValueKit

[![Platform Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2FPersistentKeyValueKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kylehughes/PersistentKeyValueKit)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2FPersistentKeyValueKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kylehughes/PersistentKeyValueKit)
[![Test](https://github.com/kylehughes/PersistentKeyValueKit/actions/workflows/test.yml/badge.svg)](https://github.com/kylehughes/PersistentKeyValueKit/actions/workflows/test.yml)

*Perfectly-shaped interfaces for `UserDefaults` and `NSUbiquitousKeyValueStore`.*

## About

PersistentKeyValueKit provides one type-safe interface for [`UserDefaults`][user-defaults-docs], [`NSUbiquitousKeyValueStore`][ubiquitous-store-docs], and an in-memory store. Define a key once and use it to read, write, remove, bind in SwiftUI, observe from async tasks or Combine, and migrate values between stores without branching on the backing store.

The library is built around three ideas:

- Define persistence logic once per value type with `KeyValuePersistible`.
- Compose custom persistence formats from reusable `PersistentKeyValueRepresentation` building blocks.
- Declare keys centrally with the static accessor pattern.

All platform constraints of [`UserDefaults`][user-defaults-docs] and [`NSUbiquitousKeyValueStore`][ubiquitous-store-docs] apply. Each app target that uses `.ubiquitous` needs the iCloud capability with Key-value storage selected, including for local reads and writes.

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

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/kylehughes/PersistentKeyValueKit.git", .upToNextMajor(from: "2.0.0")),
]
```

Add `.product(name: "PersistentKeyValueKit", package: "PersistentKeyValueKit")` to the `dependencies` of each target that imports the library.

The `PersistentKeyValueKit` target bundles an Apple privacy manifest (`PrivacyInfo.xcprivacy`) declaring `UserDefaults` access (`NSPrivacyAccessedAPICategoryUserDefaults`) with reasons `CA92.1` and `1C8F.1`.

## Documentation

This README covers common use. The [API documentation](https://kylehughes.github.io/PersistentKeyValueKit) is the reference for each symbol's contract and edge cases, including observation timing, collection and `URL` storage rules, representation requirements, and migration failure modes. Upgrading from 1.x? Read the [2.0.0 Release Notes](docs/release-notes/2.0.0.md).

## Quick Start

Conform your type to `KeyValuePersistible`. Examples declare persistible types `nonisolated` so targets with `MainActor` default isolation can use them as key values:

```swift
import PersistentKeyValueKit

nonisolated enum RuntimeColorScheme: String {
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

## Usage

### Keys and Stores

`PersistentKey<Value>` pairs a string identifier with a default value and a representation. Each logical key's identifier must be unique within its store. Define keys as static members on `PersistentKeyProtocol` for leading-dot syntax across stores, property wrappers, observation, and migration:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 0)
    }
}
```

Keys with dynamic identifiers can be static functions. Resolve the identifier when constructing the key, and keep a custom key's `id` stable for the lifetime of any migration or observation:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<String?> {
    static func selectedLayoutID(forListID listID: String) -> Self {
        Self("\(listID)::SelectedLayoutID", defaultValue: nil)
    }
}
```

The same key works with `UserDefaults` (`UserDefaults.standard` or `UserDefaults(suiteName:)`), `NSUbiquitousKeyValueStore.default`, and `InMemoryPersistentKeyValueStore` (which keeps Swift values in memory for tests and previews):

```swift
userDefaults.set(.launchCount, to: 1)

if let layoutID = NSUbiquitousKeyValueStore.default.get(.selectedLayoutID(forListID: listID)) {
    applyLayout(id: layoutID)
}
```

`store[.launchCount]` is equivalent to `store.get(.launchCount)`. Delete a persisted value with `remove(_:)`. After removal, reads return the key's `defaultValue` unless another `UserDefaults` domain, such as launch arguments or registered defaults, supplies a value.

Built-in `Bool`, numeric, and `URL` representations accept string `UserDefaults` launch arguments. `NSUbiquitousKeyValueStore` limits key identifiers to 128 UTF-16 code units.

<a name="behavior-differences"></a>
### No Implicit Defaults

Raw `UserDefaults` and `NSUbiquitousKeyValueStore` getters such as `bool(forKey:)` and `integer(forKey:)` return `false` or `0` when a key is unset. `PersistentKeyValueKit` requires an explicit `defaultValue` on every key and distinguishes missing values from stored `false` or `0`. Use an `Optional` value type with `defaultValue: nil` when `nil` should mean there is no readable value:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Bool?> {
    static var arePushNotificationsEnabled: Self {
        Self("ArePushNotificationsEnabled", defaultValue: nil)
    }
}
```

When a non-optional default suffices, use a non-optional value type:

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Bool> {
    static var arePushNotificationsEnabled: Self {
        Self("ArePushNotificationsEnabled", defaultValue: true)
    }
}
```

### `UserDefaults` Registration

Register key defaults in the `UserDefaults` registration domain when other code reads raw `UserDefaults` APIs. Because the registration domain does not persist, register on every launch in each app or extension process:

```swift
userDefaults.register(.launchCount)
```

### Keys Mutable Only in Debug Builds

`PersistentDebugKey<Value>` is mutable in Debug builds and locked to its release default in Release builds. Both `PersistentKey` and `PersistentDebugKey` require a `Sendable` value type:

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
let isRatingEnabled = userDefaults.get(.isAppStoreRatingEnabled) // Debug: false unless a higher-priority defaults value overrides it; Release: true
```

> [!WARNING]
> `PersistentDebugKey` uses `#if DEBUG` when compiling `PersistentKeyValueKit` from source; prebuilt Release binaries always take the release path.

### SwiftUI

`@PersistentValue` reads, writes, and observes a key. It uses the `defaultPersistentKeyValueStore` environment value (`UserDefaults.standard` by default) unless you pass `store:`:

```swift
@PersistentValue(.isAppStoreRatingEnabled)
var isAppStoreRatingEnabled: Bool

@PersistentValue(.isAppStoreRatingEnabled, store: .ubiquitous)
var isSyncedRatingEnabled: Bool
```

Set the default store for a view hierarchy with `.defaultPersistentKeyValueStore(_:)`. An explicit `store:` argument takes precedence:

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

When listing keys in `ForEach`, use `ForEach(keys, id: \.id.utf8CString)` so identifiers that differ only in Unicode composition stay distinct.

### Observation

`PersistentKeyValues` is an `AsyncSequence` that emits a key's current value when iteration starts, then values read on change notifications. Both the store and the key provide entry points: `store.values(for: key)` and `key.values(in: store)`. The example loops run until their tasks are cancelled, so start them in cancellable tasks (on the main actor here to update a UIKit label):

```swift
for await username in UserDefaults.standard.values(for: .username) {
    usernameLabel.text = username
}
```

Use `changes(for:)` or `changes(in:)` to skip the initial value:

```swift
for await username in UserDefaults.standard.changes(for: .username) {
    handleChange(username: username)
}
```

Pending changes default to `.bufferingNewest(1)`, so a slow consumer gets the latest value; pass `bufferingPolicy: .unbounded` to keep every emission. Each emission reads the latest value from the store, so rapid changes can arrive as one value and consecutive values can be equal.

`PersistentKeyValuePublisher` is the Combine equivalent. `publisher(for:)` and `publisher(in:)` start with the current value, while `changesPublisher(for:)` and `changesPublisher(in:)` skip it. The `for:` forms are called on the store and take a key; the `in:` forms are called on the key and take a store. Retain each returned `AnyCancellable` while its observation should run. Delivery is serial per subscription and can occur on a background thread, so use `.receive(on: DispatchQueue.main)` before updating UI. In this example, the `@MainActor` view controller has two stored properties, `usernameLabel` and `cancellables` (`Set<AnyCancellable>`):

```swift
UserDefaults.standard.publisher(for: .username)
    .receive(on: DispatchQueue.main)
    .sink { [usernameLabel] username in
        usernameLabel.text = username
    }
    .store(in: &cancellables)
```

`UserDefaults` observes most keys with key-value observation, which also sees changes from other processes such as app extensions. Keys that key-value observation cannot observe fall back to `UserDefaults.didChangeNotification`, which reports only changes made in the current process. `NSUbiquitousKeyValueStore` observation sees remote iCloud updates and local writes made through the store's `set(_:to:)` and `remove(_:)`, so use those methods and `NSUbiquitousKeyValueStore.default` everywhere. See `PersistentKeyValues` and `PersistentKeyValuePublisher` in the API documentation for delivery order, cancellation, and store differences.

### Making a Type Persistible

A type conforms to `KeyValuePersistible` by providing a `PersistentKeyValueRepresentation`:

```swift
public protocol KeyValuePersistible {
    associatedtype PersistentKeyValueRepresentation: PersistentKeyValueKit.PersistentKeyValueRepresentation<Self>

    static var persistentKeyValueRepresentation: Self.PersistentKeyValueRepresentation { get }
}
```

`Array`, `Bool`, `Data`, `Dictionary` (with `String` keys), `Double`, `Float`, `Int`, `Optional`, `String`, and `URL` are persistible when their elements are. For most other types, pick a built-in representation. You can also implement one directly.

`RawRepresentablePersistentKeyValueRepresentation` persists a `RawValue`:

```swift
nonisolated enum NotificationFrequency: String {
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

`CodablePersistentKeyValueRepresentation` encodes a `Codable` value with a Combine `TopLevelEncoder` and `TopLevelDecoder`, defaulting to `JSONEncoder()` and `JSONDecoder()`:

```swift
nonisolated struct Contact: Codable, Sendable {
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

`LosslessStringConvertiblePersistentKeyValueRepresentation` persists a `LosslessStringConvertible` value as a `String`. `ProxyPersistentKeyValueRepresentation` converts a value to and from another persistible type with closures:

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

Pass `representation:` on a key for a per-key format:

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

To implement a representation directly, provide `decode(storageObject:format:)` and `encode(_:format:)` to convert between Swift values and storage objects. Do not mutate an object after returning it from `encode` or writing it with `set`. These two methods throw and are the checked conversion. Ordinary reads and writes stay non-throwing; Foundation migration endpoints use checked conversions, and `UserDefaults` registration uses checked encoding. See `PersistentKeyValueRepresentation` for the full contract, including collection writes.

### Collections

Only homogeneous collections are persistible:

| Supported (`KeyValuePersistible`) | Not supported |
| --- | --- |
| `[Element] where Element: KeyValuePersistible` | `[any KeyValuePersistible]` |
| `[String: Value] where Value: KeyValuePersistible` | `[String: any KeyValuePersistible]` |

For structured heterogeneous data, use `CodablePersistentKeyValueRepresentation` or implement `PrimitiveKeyValuePersistible`.

Collection writes are all or nothing. With built-in element readers, an array read falls back to the key's default if any element fails to decode. A dictionary read omits entries it cannot decode, and saving the decoded dictionary back deletes those entries from the writable store, so an older client can erase an entry written by a newer client. See `Array` and `Dictionary` for details.

### Migrating Values Between Stores

Use `copy` or `move` to transfer persisted values between stores or to rename and transform keys within one store. Both require `onConflict:` and `tracking:` and return a `PersistentKeyMigrationReport`. Migration is not transactional and does not roll back completed writes. Coordinate other writers in this or any other process before migrating.

Create any named `UserDefaults` suite that takes part in a migration with `UserDefaults.migratable(suiteName:)`. `NSUbiquitousKeyValueStore` requires the Key-value storage service. This example moves two keys from standard defaults into an App Group suite; sharing preferences requires the same App Group on each target (replace `group.example.app` with its identifier):

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

Call this helper only from the target that owns the legacy defaults. A target with nothing to move still attempts to record the shared marker. If that recording succeeds, the owning target's later call returns `.alreadyRecorded` and skips migration even though `throwIfIncomplete()` succeeds. Other targets can open the suite directly.

Pass `PersistentKeyMigrationItem` values when keys change name or value type:

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

Within one store, source identifiers and destination identifiers must each be unique and the two sets must be disjoint, so changing how a key is stored requires moving it to a new key.

The conflict policy decides what happens when the destination already has a value:

| Operation | Conflict policy | Existing destination value |
| --- | --- | --- |
| Copy | `.keepDestination` | Keep destination and source values (`.keptDestination`). |
| Copy | `.overwriteDestination` | Replace destination and keep source (`.copied`). |
| Move | `.keepBoth` | Keep destination and source values (`.keptDestination`). |
| Move | `.overwriteDestination` | Replace destination, then remove source (`.moved`). |
| Move | `.keepDestinationAndRemoveSource` | Keep destination and remove source (`.discardedSource`). |

Migration reads and writes only values persisted in each store's own domain, ignoring registered defaults, launch arguments, and `defaultValue`. For a `UserDefaults` or `NSUbiquitousKeyValueStore` destination, a successful write leaves the destination entry absent only when the value is `nil` at an actual `Optional` layer and encodes to `nil`; any other value that encodes to `nil` fails that item at `.prepare`, writing neither entry. A type-changing `UserDefaults` replacement can temporarily remove the old entry before storing the new object.

Setup problems throw before any item runs. A failure in one item is recorded in `report.outcomes` while remaining items continue, and `try report.throwIfIncomplete()` throws if any item or completion marker failed:

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

With `.once(id:)`, migration attempts to record a completion marker once every item resolves without failure. After setup succeeds, a true marker for that `id` in the selected recording store skips the batch (`.alreadyRecorded`). Remove the `.isMigrationCompleted(id:)` marker from the recording store or choose a new `id` to run a migration again.

Give each independent source its own completion marker; sources that share a recording store need distinct `id` values. A marker in `NSUbiquitousKeyValueStore` syncs across devices, so record local-to-iCloud migrations in local defaults with `recordedIn:`, as shown above. Migration does not wait for iCloud's initial sync, so seed or migrate from iCloud only after the current account's data arrives.

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
