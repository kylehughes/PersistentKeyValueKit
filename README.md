# PersistentKeyValueKit

[![Platform Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2FPersistentKeyValueKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kylehughes/PersistentKeyValueKit)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2FPersistentKeyValueKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kylehughes/PersistentKeyValueKit)
[![Test](https://github.com/kylehughes/PersistentKeyValueKit/actions/workflows/test.yml/badge.svg)](https://github.com/kylehughes/PersistentKeyValueKit/actions/workflows/test.yml)

*Perfectly-shaped interfaces for `UserDefaults` and `NSUbiquitousKeyValueStore`.*

## About

PersistentKeyValueKit provides a comprehensive, type-safe, and universal interface for `UserDefaults` and 
`NSUbiquitousKeyValueStore`. It makes it easy to persist and retrieve any type from storage throughout your codebase. 
The framework encourages:

- Defining persistence logic on a per-type basis
- Composing persistence logic from common building blocks
- Using the static accessor pattern to centrally define keys

PersistentKeyValueKit is heavy with opinions, concepts, and types, but the implementation is lightweight and tries to 
sit right on top of the familiar storage APIs.

All constraints of [`UserDefaults`][user-defaults-docs] and [`NSUbiquitousKeyValueStore`][ubiquitous-store-docs] apply. 
Familiarity with these storage systems is recommended. Data is not automatically migrated between stores.

PersistentKeyValueKit is backed by a robust test suite.

[ubiquitous-store-docs]: https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore
[user-defaults-docs]: https://developer.apple.com/documentation/foundation/userdefaults

### Capabilities

- [x] Strongly-typed key-value pairs.
- [x] Persistence for any type that conforms to `KeyValuePersistible`.
- [x] Universal interface for `UserDefaults` and `NSUbiquitousKeyValueStore`.
- [x] Type-safe property wrapper and view modifier for SwiftUI.
- [x] Built-in support for all primitive (i.e. property list) types.
- [x] Built-in representations for all common ways to persist values.
- [x] Keys that are only mutable in Debug builds.
- [x] Swift 6 language mode support.

## Supported Platforms

- iOS 15.0+
- macOS 13.0+
- tvOS 15.0+
- visionOS 1.0+
- watchOS 8.0+
    - `NSUbiquitousKeyValueStore` requires watchOS 9.0+.

## Requirements

- Xcode 16.0+

## Documentation

[Documentation is available on GitHub Pages](https://kylehughes.github.io/PersistentKeyValueKit).

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/kylehughes/PersistentKeyValueKit.git", .upToNextMajor(from: "1.0.0")),
]
```

## Quick Start

Make a type persistible by conforming to `KeyValuePersistible`.

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

Define a key whose value is the type.

```swift
import PersistentKeyValueKit

extension PersistentKeyProtocol where Self == PersistentKey<RuntimeColorScheme> {
    static var runtimeColorScheme: Self {
        Self("RuntimeColorScheme", defaultValue: .system)
    }
}
```

Use the value in a SwiftUI view…

```swift
import PersistentKeyValueKit

struct SettingsView: View {
    @PersistentValue(.runtimeColorScheme)
    var runtimeColorScheme
}
```

…or anywhere else.

```swift
userDefaults.get(.runtimeColorScheme)
```

```swift
userDefaults.set(.runtimeColorScheme, to: .dark)
```

## Usage

### Keys

#### Define and Access a Key

A `PersistentKey<Value>` maps a unique identifier to a strongly-typed `Value` that persists between launches of an 
application.

It is recommended to use the static accessor pattern to define and access keys. This pattern allows you to define keys 
in common locations and access them anywhere in a type-safe manner. The APIs are designed to be as ergonomic as possible
for this pattern.

e.g.

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Date> {
    static var mostRecentLaunchDate: Self {
        Self("MostRecentLaunchDate", defaultValue: .distantPast)
    }
}
```

Dynamically-identified keys can be defined with static accessors as well.

e.g.

```swift
extension PersistentKeyProtocol where Self == PersistentKey<String?> {
    static func selectedLayoutID(forListID listID: String) -> Self {
        Self("\(listID)::SelectedLayoutID", defaultValue: nil)
    }
}
```

Key-value pairs can be stored locally in `UserDefaults`—e.g. `UserDefaults.standard`, `UserDefaults(suiteName:)`— or in
iCloud in `NSUbiquitousKeyValueStore.default`.

e.g.

```swift
userDefaults.set(.mostRecentLaunchDate, to: .now)
```

```swift
if let layoutID = NSUbiquitousKeyValueStore.default.get(.selectedLayoutID(forListID: listID)) {
```

#### Define and Access a Debug Key

A debug key is a key whose value is modifiable in Debug builds but not in Release builds. This lets you use keys
for development and testing purposes without worrying about them being modifiable in production, and while minimizing 
the amount of conditional code you need to write.

All key-based interfaces accept `PersistentKeyProtocol`, which both `PersistentKey` and `PersistentDebugKey` conform to.

> [!WARNING]
> Debug keys will only work if compiling this framework from source (e.g. as a SwiftPM dependency). If using a pre-built 
> binary then the `DEBUG` code paths will likely not be included and default values will always be used.

e.g.

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
```

```swift
userDefaults.set(.isAppStoreRatingEnabled, to: false)
```

```swift
userDefaults.get(.isAppStoreRatingEnabled) // false in Debug, true in Release
```

### Make a Type Persistible

Make a type persistible by conforming to `KeyValuePersistible`.

`KeyValuePersistible` has one requirement: 

```swift
static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> { get }
```

A representation is a type that describes how a value is persisted: how it is stored inside of `UserDefaults` or 
`NSUbiquitousKeyValueStore`, and how it is retrieved. 

Many common representations are provided and it is easy to build custom ones inside of the `KeyValuePersistible` 
implementation. The primitive types for the stores are natively represented, so your responsibility is to transform your 
type to-and-from a primitive one.

e.g.

```swift
extension UIContentSizeCategory: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}
```

#### Primitive Types

Primitive types are natively supported by `UserDefaults` and/or `NSUbiquitousKeyValueStore`. These types are all 
`KeyValuePersistible` and are stored directly with little-to-no transformation. All other `KeyValuePersistible` 
types must be transformed into a primitive type through a `PersistentKeyValueRepresentation`.

The primitive types are:

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

### Persistence Representations

There are built-in representations that cover the most common use cases for applications. They are all described here. 
Their building blocks are available if necessary, but not described here.

#### `ProxyPersistentKeyValueRepresentation`

`ProxyPersistentKeyValueRepresentation` is a representation that uses the representation of `Proxy` as its own. The 
`Proxy` type must be a `KeyValuePersistible` type.

Use this representation to rely on an existing representation that's suitable for the type.

This is the base representation for types to build on top of. A common pattern is to use a primitive type as the proxy 
type, but any `KeyValuePersistible` type can be used as the proxy type. There is no limit to the layers of indirection.

e.g.

`Date` is persisted as `TimeInterval` (i.e. `Double`).

```swift
extension Date: KeyValuePersistible {
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        ProxyPersistentKeyValueRepresentation(
            to: \.timeIntervalSinceReferenceDate,
            from: Date.init(timeIntervalSinceReferenceDate:)
        )
    }
}
```

#### `RawRepresentablePersistentKeyValueRepresentation`

`RawRepresentablePersistentKeyValueRepresentation` is a proxy representation that persists a `RawRepresentable` value as 
its `RawValue`, if `RawValue` is `KeyValuePersistible`.

e.g.

`NotificationFrequency` is persisted as `String`.

```swift
enum NotificationFrequency: String {
    case daily
    case weekly
    case monthly
}
```

```swift
extension NotificationFrequency: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}
```

#### `CodablePersistentKeyValueRepresentation`

`CodablePersistentKeyValueRepresentation` is a proxy representation that persists a value as the `Input`/`Output` type
of the given encoder and decoder.

e.g.

`Contact` is persisted as `Data`.

```swift
struct Contact: Codable, Sendable {
    let nickname: String
    let dateOfBirth: Date
}
```

```swift
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension Contact: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        CodablePersistentKeyValueRepresentation()
    }
}
```

This convenience initializer is provided for the default `JSONDecoder` and `JSONEncoder`. The `Decoder` and `Encoder` 
can be supplied in other initializers.

#### `LosslessStringConvertiblePersistentKeyValueRepresentation`

`LosslessStringConvertiblePersistentKeyValueRepresentation` is a proxy representation that persists a value as a 
`String`, as defined by its `LosslessStringConvertible` conformance.

e.g.

`Character` is persisted as `String`.

```swift
extension Character: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        LosslessStringConvertiblePersistentKeyValueRepresentation()
    }
}
```

#### Custom Representation for a Single Key

Every `KeyValuePersistible` type has an associated `PersistentKeyValueRepresentation` type and 
`persistentKeyValueRepresentation` property. This is the default representation used to persist the value with a store.

However, a representation for a single key can be provided at definition time—even if the value isn't 
`KeyValuePersistible`. This is useful for:

- One-off keys for nonconforming types.
- Handling older values stored differently from the default representation.

e.g.

`Date?` is persisted as `String` using the ISO 8601 format.

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Date?> {
    static var mostRecentAppStoreReviewRequestDate: Self {
        Self(
            "MostRecentAppStoreReviewRequestDate",
            defaultValue: nil,
            representation: ProxyPersistentKeyValueRepresentation(
                to: { date in date.ISO8601Format() },
                from: { string in try? Date.ISO8601FormatStyle().parse(string) }
            )
        )
    }
}
```

### SwiftUI

#### Property Wrapper

`PersistentValue` is a property wrapper that provides a type-safe way to access and modify values from `UserDefaults` or 
`NSUbiquitousKeyValueStore` in SwiftUI views. It supports automatic observation and updates whenever the value changes
in the given store, locally or otherwise.

The default store is the `defaultPersistentKeyValueStore` from the environment. If unset, the default store is
`UserDefaults.standard`.

e.g.

```swift
@PersistentValue(.isAppStoreRatingEnabled)
var isAppStoreRatingEnabled: Bool
```

```swift
@PersistentValue(.isAppStoreRatingEnabled, store: .ubiquitous)
var isAppStoreRatingEnabled: Bool
```

##### View Modifier

A view modifier is provided to set the default store used by any `@PersistentValue` property wrapper in the view (or 
its descendants). The default store can be overridden by supplying one directly in the `@PersistentValue` declaration.

e.g.

```swift
extension App: SwiftUI.App {
    var body: some Scene {
        RootView()
            .defaultPersistentKeyValueStore(.ubiquitous)
    }
}
```

### `UserDefaults` Registration

PersistentKeyValueKit supports traditional `UserDefaults` registration. The default value of the key will be registered
as the default value in the registration domain of the instance of `UserDefaults`.

e.g.

`1` will be registered for key `LaunchCount` in the defaults dictionary in the registration domain for `UserDefaults`.

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 1)
    }
}
```

```swift
userDefaults.register(.launchCount)
```

> [!NOTE]
> Registration isn't necessary when using PersistentKeyValueKit exclusively since default values are handled through key 
> definitions. It becomes useful when sharing `UserDefaults` with other frameworks that don't use PersistentKeyValueKit, 
> ensuring default values are available to code using raw `UserDefaults` APIs.

## Important Behavior Differences

PersistentKeyValueKit strives to be type-safe infrastructure on top of the platform storage APIs. Behavior is changed
only when it was overwhelmingly idiomatic, modern, or necessary to do so.

### No Implicit Defaults

The platform storage APIs use implicit defaults. For example, `UserDefaults` will return `false` for `Bool` values for
keys that are not set (or removed), or `0` for `Int`. There is no way to distinguish these implicit values from an 
unset key; no way to represent a `nil` value, or the absence of a value.

PersistentKeyValueKit requires an explicit default value for every key. This is the value that will be returned for an 
unset key, or key with the wrong type of value. It can be different for each key. This provides granular control over 
the value, as well as type-safe optionality. If the key needs to represent a `nil` value, or absence of a value, then 
the key can be defined with an `Optional` type and its default value can be `nil`.

e.g.

This key's value can be `nil`, and if no value is set then `nil` will be returned. The caller can distinguish an unset
key from a `true` or `false` value.

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Bool?> {
    static var arePushNotificationsEnabled: Self {
        Self("ArePushNotificationsEnabled", defaultValue: nil)
    }
}
```

This key's value cannot be `nil` and will return `true` if no value is set. The caller cannot distinguish an unset key
from a `true` value.

```swift
extension PersistentKeyProtocol where Self == PersistentKey<Bool> {
    static var arePushNotificationsEnabled: Self {
        Self("ArePushNotificationsEnabled", defaultValue: true)
    }
}
```

> [!NOTE]
> An enum with three cases is often better than an `Optional<Bool>` for absolute clarity in what the absence of a 
> boolean value means.

### No Heterogeneous Collections

The platform storage APIs support heterogeneous arrays (`Array<Any>`) and dictionaries (`Dictionary<String, Any>`).

PersistentKeyValueKit does not natively support heterogeneous collections for the sake of ergonomics. Overlapping
protocol conformances (i.e. for `KeyValuePersistible`) are not allowed, so the decision was made to favor homogeneous
collections that are more frequently used in Swift.

i.e.

| ✅ `KeyValuePersistible`                           | ❌ `KeyValuePersistible`            |
| ---------------------------------------------------| ------------------------------------|
| `[Element] where Element: KeyValuePersistible`     | `[any KeyValuePersistible]`         |
| `[String: Value] where Value: KeyValuePersistible` | `[String: any KeyValuePersistible]` |

Heterogeneous arrays are unwieldy to use with Swift: the caller needs to know the type at each index. Heterogeneous 
dictionaries are understandable—serializing keyed types—but properly supporting them within the framework delivered no 
performance benefit over using a `Codable` representation.

Heterogeneous collections can be used by conforming a type to `PrimitiveKeyValuePersistible` and interfacing with the 
storage APIs directly. This is the fastest way to persist a keyed type. This is not recommended—there are no 
affordances for property list safety or proxy representations—but it is available.

### Limited `NSUbiquitousKeyValueStore` Observability

There is no platform support for observing changes to keys in `NSUbiquitousKeyValueStore`. The only affordance is
listening for external changes from other devices. PersistentKeyValueKit implements observability for all mutations
made through the framework: any `@PersistentValue` using `NSUbiquitousKeyValueStore` will automatically update with any
changes made by PersistentKeyValueKit anywhere, on any device. However, any changes to `NSUbiquitousKeyValueStore` made 
outside of the framework will not be automatically reflected in `@PersistentValue` properties.

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
