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

Add `.product(name: "PersistentKeyValueKit", package: "PersistentKeyValueKit")` to the dependencies of each target that imports the library.

The `PersistentKeyValueKit` target bundles an Apple privacy manifest (`PrivacyInfo.xcprivacy`) declaring `UserDefaults` access (`NSPrivacyAccessedAPICategoryUserDefaults`) with reasons `CA92.1` and `1C8F.1`.

## Quick Start

Conform your type to `KeyValuePersistible`. The examples declare persistible types `nonisolated` so that a target whose default isolation is `MainActor` can use them as a key's value:

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

Observe changes with Combine, retaining the returned `AnyCancellable` for as long as the observation should run. These examples run in a view controller that has `userDefaults` and `cancellables` (a `Set<AnyCancellable>`) as stored properties and `apply(_:)` as a method, so the closure captures `self` weakly to call it:

```swift
userDefaults.publisher(for: .runtimeColorScheme)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] runtimeColorScheme in
        self?.apply(runtimeColorScheme)
    }
    .store(in: &cancellables)
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

Resolve a dynamic identifier when constructing each key, and keep a custom key's `id` stable throughout a migration and for the lifetime of an observation. Keep the complete `NSUbiquitousKeyValueStore` key identifier, including any generated prefix or suffix, within 128 UTF-16 code units; Foundation can raise an exception when a write exceeds that limit. Migration reports `.keyIdentifierTooLong` during setup.

The same key works with `UserDefaults` (`UserDefaults.standard` or `UserDefaults(suiteName:)`), `NSUbiquitousKeyValueStore.default`, and `InMemoryPersistentKeyValueStore`:

```swift
userDefaults.set(.launchCount, to: 1)

if let layoutID = NSUbiquitousKeyValueStore.default.get(.selectedLayoutID(forListID: listID)) {
    applyLayout(id: layoutID)
}
```

Values can also be read by subscript (`store[.launchCount]`) and removed from the persistent domain with `remove(_:)` (reads then return `defaultValue` unless another `UserDefaults` domain, such as launch arguments or registered defaults, supplies a value). Built-in `Bool`, numeric, and `URL` representations coerce `UserDefaults.argumentDomain` strings (a `URL` argument requires a scheme) unless a managed preference overrides the key; optionals and proxies inherit this. `InMemoryPersistentKeyValueStore` keeps Swift values in memory for tests and previews; class instances are shared, so use immutable or `Sendable` reference types across concurrency domains, and note that mutating one in place does not notify observers.

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

Pending changes default to `.bufferingNewest(1)`. Pass `bufferingPolicy: .unbounded` to retain every value the sequence emits:

```swift
for await username in UserDefaults.standard.changes(for: .username, bufferingPolicy: .unbounded) {
    recordChange(username: username)
}
```

Each change emission reads the latest value from the store (several store change reports can produce one read and one emitted value, even with `.unbounded`, and consecutive values can be equal). Iterators deregister on termination or deinitialization, and `next()` returns `nil` and releases buffered values when the task is cancelled while it waits or before it is called.

#### Combine Publishers

`PersistentKeyValuePublisher` is a Combine `Publisher` (`Failure == Never`). `publisher(for:)` and `publisher(in:)` read the current value on subscription and deliver it on first demand, followed by subsequent changes; `changesPublisher(for:)` and `changesPublisher(in:)` skip that initial read. Retain each returned `AnyCancellable` for as long as the observation should run; these examples store it in a `Set<AnyCancellable>` named `cancellables`. They run in a `@MainActor` view controller with stored `usernameLabel` and `cancellables` properties and a `handleChange(username:)` method. Closures that use those members capture the label directly (`[usernameLabel]`) or capture `self` weakly:

```swift
UserDefaults.standard.publisher(for: .username)
    .receive(on: DispatchQueue.main)
    .sink { [usernameLabel] username in
        usernameLabel.text = username
    }
    .store(in: &cancellables)

let usernameKey: PersistentKey<String> = .username
usernameKey.publisher(in: UserDefaults.standard)
    .receive(on: DispatchQueue.main)
    .sink { [usernameLabel] username in
        usernameLabel.text = username
    }
    .store(in: &cancellables)
```

To skip the initial value, use `changesPublisher(for:)`:

```swift
UserDefaults.standard.changesPublisher(for: .username)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] username in
        self?.handleChange(username: username)
    }
    .store(in: &cancellables)
```

Delivery is synchronous and serialized for each subscription. A thread already delivering values can deliver work that other threads queued, so a setter returning does not mean its update has been delivered. While a subscriber is in `receive(subscription:)`, only the subscribing thread delivers values, so blocking there for another thread's value will hang; when `receive(subscription:)` returns, the subscribing thread delivers any deliverable values still queued. Use `.receive(on: DispatchQueue.main)` before updating UI. Exhausted demand coalesces intermediate updates, and several changes reported during one delivery can produce a single later read even with unlimited demand, so consecutive delivered values can also be equal. Subscriptions deregister when cancelled or released.

For `UserDefaults` keys KVO cannot observe (empty keys, keys starting with `@`, keys containing a `.` code unit even in a combined character, keys containing NUL, and `valueForKey:` / `ValueForKey:`), observation uses `UserDefaults.didChangeNotification` instead (in-process defaults notifications request a read of the effective value, and several notifications can share one read of each key, so cross-process and `addSuite(named:)` / `removeSuite(named:)` changes appear only on a later read, and the fallback compares the widths of the integers it reads); other keys use KVO and also see cross-process changes, though Foundation does not post KVO for a write it considers equal to the stored value (such as `Int64` over an equal `Int32` or `-0.0` over `0.0`), so a subscriber can keep the previous, numerically equal value.

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

`Array` and `Dictionary` writes to `UserDefaults` and `NSUbiquitousKeyValueStore` are all-or-nothing, and the built-in collection representations omit `Optional` `nil` elements at every nesting level. The default in-memory setter compacts only a qualifying top-level Swift array or `String`-keyed dictionary of optionals, and a key can override that setter. For external representations, the default array writer omits an element whose `encode` returns `nil`, and a container hook that leaves a dictionary entry absent (as the default hook does when `encode` returns `nil`), leaves the array empty for non-empty input, or produces objects that stores cannot persist (such as keyed-archive UIDs or cycles; store archives as `Data`) leaves the store unchanged on ordinary writes and throws `.encodingFailed` in checked encoding (used by migration and by `UserDefaults.register(_:)`, which skips a default that fails). Ordinary `Array` reads of built-in element representations are all-or-nothing: if one element fails to decode, the key returns its default array, and saving an edit to that default replaces the stored array, including the elements that could decode. Ordinary `Dictionary` reads omit undecodable entries but leave them in storage, so writing the decoded dictionary back replaces the whole dictionary in the writable defaults domain and deletes the omitted entries there, even if you edited only a different key (if an added suite supplied the dictionary, the write hides that suite's dictionary, which keeps its entries). Checked decoding (migration) of built-in representations fails on any undecodable element or entry. An external array or dictionary-entry reader can filter elements or nested entries during ordinary and checked reads, including through an optional, proxy, or nested collection that reaches it. Checked dictionary decoding fails when an external entry reader returns `nil`, but accepts a value from which that reader has already omitted nested entries.

`URL` supports absolute URLs and relative references. Checked `.userDefaults` decoding reads stored paths like `UserDefaults.url(forKey:)` (throwing `.invalidStorageValue` when it returns `nil`), and checked encoding requires the stored path to reproduce the file URL's `absoluteString` (rejecting, for example, a file URL host or a nonexistent directory's trailing slash), so a relative reference's original `baseURL` can be lost, and because each read rebuilds a file URL from its stored path, deleting a directory can drop its trailing slash and change how relative URLs resolve. Ordinary `set` keeps Foundation's storage (paths for file URLs, archive data for other URLs), and `[URL]` and iCloud storage keep only `absoluteString`, so a relative URL with an absolute base reads back as its resolved URL without its base.

#### `RawRepresentablePersistentKeyValueRepresentation`

`RawRepresentablePersistentKeyValueRepresentation` persists a `RawRepresentable` type as its `RawValue` when `RawValue` conforms to `KeyValuePersistible`:

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

#### `CodablePersistentKeyValueRepresentation`

`CodablePersistentKeyValueRepresentation` encodes and decodes a `Codable` value with a `Sendable` Combine `TopLevelEncoder` and `TopLevelDecoder` whose shared output and input type conforms to `KeyValuePersistible` (defaulting to `JSONEncoder()` and `JSONDecoder()`):

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

An object returned from `encode`, returned from a proxy `to`, or written by any `set` method is handed over and must not be mutated afterward (including mutable strings, data buffers, dictionary keys, or containers); behavior is unspecified otherwise. Array `set(_:to:)` hooks may only assign or append to the empty array passed in, and dictionary `set(_:to:in:)` hooks may access only the entry for the given key. Proxy representations (`ProxyPersistentKeyValueRepresentation` and `ProxyPersistentKeyValueRepresentationProtocol`) derive `decode` and `encode` from `from(_:)` and `to(_:)`, and direct `PersistentKeyValueRepresentation` or `PrimitiveKeyValuePersistible` conformers inherit default store and container methods built on `decode` and `encode`. Put Foundation migration conversion in `encode` and `decode`: migration does not call a wrapper store's or a key's ordinary accessors, but collection conversion honors external array and dictionary hooks (see the [2.0.0 Release Notes](docs/release-notes/2.0.0.md)).

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

Same-store migrations are allowed when every item maps its source key to a different destination key (no duplicate or overlapping keys); in-place rewrites are not supported, and any same-store item whose source and destination key identifiers are the same throws `PersistentKeyMigrationError.sameStore` at setup before any key is read. To change a key's stored representation or value format, migrate it to a new key ID with `move` (when a batch runs again, an item reports `.keyDisabled` if either key is disabled, and an enabled item whose source is absent, as after a `move`, reports `.sourceAbsent`; a keep policy skips `transform` when a destination entry exists, and runs it again when the source remains and the destination is absent; `.overwriteDestination` replaces the earlier result, running `transform` again).

`transform` runs in input order after source decoding, when both keys are enabled (`isMigrationEnabled == true`) and the conflict policy selects a write (a later failure can still prevent the write); if it throws, the item fails at `.transform` and writes to neither store. An `InMemoryPersistentKeyValueStore` source passes stored Swift values without running representation codecs, so copy a mutable reference input in `transform` before mutating it.

#### Conflict Policies and Partial Changes

| Operation | Conflict policy | Existing destination value |
| --- | --- | --- |
| Copy | `.keepDestination` | Verify destination unchanged, then keep destination and source values (`.keptDestination`). |
| Copy | `.overwriteDestination` | Replace destination and keep source (`.copied`). |
| Move | `.keepBoth` | Verify destination unchanged, then keep destination and source values (`.keptDestination`). |
| Move | `.overwriteDestination` | Replace destination, then remove source (`.moved`). |
| Move | `.keepDestinationAndRemoveSource` | Verify destination unchanged, then remove source (`.discardedSource`). |

`.keepBoth` on a `move` leaves conflicting source values in place; use `.keepDestinationAndRemoveSource` or `.overwriteDestination` to remove conflicting source entries. The keep policies decode neither value of an existing conflict, so `.keepDestinationAndRemoveSource` can discard an unreadable source, or the only readable value when the key cannot decode the destination. A Foundation destination stores the object its key's representation encodes, and a `nil` encoding removes the entry (as the built-in optional representation does for `nil`), so a successful move can leave both entries absent. An in-memory destination bypasses the key's representation: it keeps an explicit optional `nil` and applies the ordinary setter's shallow compaction to a qualifying array or dictionary of optionals, including one wrapped in an `Optional`. Only values persisted in each store's own domain participate (registered defaults, launch arguments, added suites, and `defaultValue` are ignored).

Setup errors (`PersistentKeyMigrationError`, or an error a store's `migrationEndpoint` throws, which propagates unchanged) throw before any item runs, as does an error reading a tracked batch's completion marker (an undecodable marker throws `.invalidCompletionRecord`). A tracked migration requires a nonempty ID, and a concurrent in-process migration using any of the same store and key pairs, including the completion marker, throws `.overlappingMigration`; other writers and processes need separate coordination. Per-item failures go into `report.outcomes` (`.failed(FailureStage)` with `outcome.error`) as remaining items continue. Foundation writes fail at `.prepare` with `.encodingFailed` when the encoded object cannot persist as is (such as keyed-archive UIDs, or an `NSDecimalNumber`, which serialization stores as a `Double`) or, for an iCloud destination, with `.invalidStorageValue` when its binary property list exceeds 1 MiB; iCloud also limits the store to 1 MB in total and 1,024 keys, including a completion marker recorded there. Preparation verifies that the object decodes and that serialization preserves it, comparing integers by value across widths, so a decoder of persisted values must accept widened integers. A custom representation determines how much of the original Swift value survives (the ISO 8601 date above stores whole seconds). At `.write`, a destination that appeared, disappeared, or differs from its snapshot when checked produces `.destinationChanged`, before any attempt to remove the source (when Foundation considers the old and new objects equal but migration verification distinguishes them, `UserDefaults` temporarily removes the entry and checks that it remains absent before writing, so a change undone before that check can go undetected), and a committed value that fails verification produces `.writeVerificationFailed`. Migrations do not roll back completed writes: at `.cleanup`, `.sourceChanged` means the move skipped removal, `.destinationChanged` means the destination differed after the source was removed, and `.removalVerificationFailed` means the source held a value after the removal attempt (the original entry may have remained, or a writer may have restored it); another writer may have changed either key, and a write between a move's source check and its removal is deleted even when the move reports `.moved`. Coordinate other writers, processes, and reentrant callbacks (getters, `deinit`, allocators, observers) before migrating, or behavior is unspecified. Local completion does not guarantee disk durability or iCloud delivery, and removing an iCloud key deletes it across devices.

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

`PersistentKeyMigrationTracking` provides `.untracked` (`report.completion` is `.untracked`), `.once(id:)` (recorded in the destination store), and `.once(id:recordedIn:)`. With `.once`, `.isMigrationCompleted(id:)` is recorded once every item resolves without failure (`.recorded`), including skipped items, so a batch that transferred nothing is still recorded, and later calls skip the whole batch (`.alreadyRecorded`), including keys that arrived later; if any item fails, `report.completion` is `.notRecorded`, and if recording or verifying the marker fails, `report.completion` is `.failed` with `report.completionError`. A retry reads the stored marker again, so a marker that was written but failed verification can still be honored. An item failure, or a failure to record or verify the marker, leaves `report.isComplete == false`, causing `try report.throwIfIncomplete()` to throw `PersistentKeyMigrationIncompleteError`; an error reading the initial marker throws before the batch runs. Until a `.once` marker is recorded, retrying re-runs the batch under its conflict policy; remove `.isMigrationCompleted(id:)` (or set it to `false`) to reset tracking, or pick a new `id` when changing a migration.

A marker recorded in `NSUbiquitousKeyValueStore` syncs across devices, so two devices can both run the migration before it syncs; pass `.once(id:recordedIn: UserDefaults.standard)` to record a local-to-iCloud migration in this target's local defaults instead. A marker depends only on its `id` and recording store, so give each independent source that migrates into a shared App Group its own `id` or `recordedIn:` store; the second source otherwise reports `.alreadyRecorded` and never transfers. When migrating *from* `NSUbiquitousKeyValueStore` with both keys enabled, a source missing from the local cache before initial sync reports `.sourceAbsent` on that run, and if the batch records completion, later calls with that marker skip every item, including keys that have since synced; use `.untracked` until initial sync completes or record completion yourself. Conflict checks against an iCloud destination likewise read this device's local cache, so to preserve existing cloud preferences, wait for the current account's initial data before seeding; migration does not wait for sync.

#### Named `UserDefaults` Suites

Any named `UserDefaults` suite a migration reads, writes, or uses for `recordedIn:` must be created with `UserDefaults.migratable(suiteName:)`, returning the native `UserDefaults` instance with process-local domain metadata attached for its lifetime (`nil` for empty, NUL-containing, path-shaped, `.plist`-suffixed, or reserved domain names). `UserDefaults.standard` (requiring a non-empty `Bundle.main.bundleIdentifier`, or throwing `.missingApplicationIdentifier`), `NSUbiquitousKeyValueStore.default`, and `InMemoryPersistentKeyValueStore` need no special setup, and ordinary `UserDefaults(suiteName:)` instances work outside migrations. See the [2.0.0 Release Notes](docs/release-notes/2.0.0.md) and the [native-store migration decision record](docs/decisions/2026-09-15-native-store-migration.md) for validation and verification details.

### `UserDefaults` Registration

Register key default values in the `UserDefaults` registration domain with `register(_:)` when sharing `UserDefaults` with code that reads raw `UserDefaults` APIs:

```swift
userDefaults.register(.launchCount)
```

`register(_:)` encodes each key's `defaultValue` using `.userDefaults` format (skipping defaults that fail checked `.userDefaults` encoding, such as file `URL`s whose stored path cannot reproduce their `absoluteString`, for which typed `get(_:)` still returns `defaultValue` while raw `url(forKey:)` returns `nil` when no other value is visible). A `nil` encoding removes the key from the dictionary being filled, while a default already submitted in a separate `UserDefaults.register(_:)` call remains registered.

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
