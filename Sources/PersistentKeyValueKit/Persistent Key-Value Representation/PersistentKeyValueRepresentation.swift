//
//  PersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore``.
///
/// Conforming types implement ``decode(storageObject:format:)`` and ``encode(_:format:)``. The store-specific `get`
/// and `set` methods have default implementations built on those conversions; implement them only to customize
/// access to a particular store.
public protocol PersistentKeyValueRepresentation<Value>: Sendable {
    // MARK: Associated Types
    
    /// The type of value that is represented in a ``PersistentKeyValueStore``.
    associatedtype Value

    /// Decodes a value from a stored object for the given storage format.
    ///
    /// Callers such as migration write validation may invoke conversion more than once for the same value; do not
    /// rely on a specific invocation count.
    ///
    /// - Parameter storageObject: The stored object read from the backing store or property-list container.
    /// - Parameter format: The storage format of `storageObject`.
    /// - Returns: The decoded value.
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value

    /// Encodes a value into a stored object for the given storage format.
    ///
    /// Returning `nil` removes the key from a store. The default container methods omit such a value from a
    /// property-list collection, but an omission that leaves a dictionary entry absent or a nonempty array empty fails
    /// the write; see ``set(_:to:in:)`` and ``set(_:to:)``. Callers such as migration write validation may invoke
    /// conversion more than once for the same value; do not rely on a specific invocation count.
    ///
    /// - Parameter value: The value to encode.
    /// - Parameter format: The target storage format.
    /// - Returns: The encoded storage object, or `nil` to remove the key.
    func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any?
    
    // MARK: Interfacing with Property List Array
    
    /// Decodes the elements of `propertyListArray` as ``Value``.
    ///
    /// Array reads decode a stored array with this method, so it must accept the arrays that ``set(_:to:)`` writes.
    /// Checked conversion, which migration and `UserDefaults.register(_:)` use, also calls this method for
    /// representations defined outside this package, so an implementation that omits elements it cannot decode omits
    /// them from migrated values too.
    ///
    /// - Parameter propertyListArray: The array to decode values from.
    /// - Returns: The decoded values, or `nil` if any element cannot be decoded as ``Value``.
    func get(from propertyListArray: [Any]) -> [Value]?

    /// Writes the encoded representations of `values` into `propertyListArray`.
    ///
    /// Array writes, registration, and migration call this method with an empty `propertyListArray`, and an
    /// implementation may either assign the encoded array or append the encoded elements to it. The result is the
    /// stored form of `values` and need not contain each element's own encoding. If any value fails to encode, leave
    /// `propertyListArray` unchanged. Callers rely on this to keep the stored collection when one of its elements
    /// cannot be encoded, so an empty result for nonempty `values` counts as a failure, even if every value encodes to
    /// `nil`.
    ///
    /// - Parameter values: The values to encode into `propertyListArray`.
    /// - Parameter propertyListArray: The array to write the encoded values into.
    func set(_ values: [Value], to propertyListArray: inout [Any])
    
    // MARK: Interfacing with Property List Dictionary

    /// Decodes the value at `dictionaryKey` in `propertyListDictionary`, if present and representable as ``Value``.
    ///
    /// Dictionary reads decode a stored entry with this method, so it must accept the objects that ``set(_:to:in:)``
    /// writes. Ordinary dictionary reads omit an entry for which this method returns `nil`. Checked conversion, which
    /// migration and `UserDefaults.register(_:)` use, also calls this method for representations defined outside this
    /// package and fails instead.
    ///
    /// - Parameter dictionaryKey: The key to look up.
    /// - Parameter propertyListDictionary: The dictionary to read from.
    /// - Returns: The decoded value at `dictionaryKey` in `propertyListDictionary`, or `nil` if it is absent or cannot
    ///   be decoded as ``Value``.
    func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value?

    /// Sets the value at `dictionaryKey` in `propertyListDictionary`.
    ///
    /// If `value` fails to encode, leave `propertyListDictionary` unchanged; if it encodes to `nil`, remove
    /// `dictionaryKey`. Dictionary writes, registration, and migration call this method for a `dictionaryKey` that
    /// `propertyListDictionary` does not yet contain, and rely on this to keep the stored dictionary when one of its
    /// values cannot be encoded, so an absent entry counts as a failure, even if the value encodes to `nil`.
    ///
    /// - Parameter dictionaryKey: The key to update.
    /// - Parameter value: The value to encode.
    /// - Parameter propertyListDictionary: The dictionary to update at `dictionaryKey`.
    func set(_ dictionaryKey: String, to value: Value, in propertyListDictionary: inout [String: Any])
    
    // MARK: Interfacing with User Defaults
    
    /// Decodes the value at `userDefaultsKey` in `userDefaults`, if present and representable as ``Value``.
    ///
    /// - Parameter userDefaultsKey: The key to look up.
    /// - Parameter userDefaults: The `UserDefaults` instance to read from.
    /// - Returns: The decoded value at `userDefaultsKey` in `userDefaults`, or `nil` if it is absent or cannot be
    ///   decoded as ``Value``.
    func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value?
    
    /// Sets the value at `userDefaultsKey` in `userDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to update.
    /// - Parameter value: The value to encode.
    /// - Parameter userDefaults: The `UserDefaults` instance to update at `userDefaultsKey`.
    func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Decodes the value at `ubiquitousStoreKey` in `ubiquitousStore`, if present and representable as ``Value``.
    ///
    /// - Parameter ubiquitousStoreKey: The key to look up.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` instance to read from.
    /// - Returns: The decoded value at `ubiquitousStoreKey` in `ubiquitousStore`, or `nil` if it is absent or cannot
    ///   be decoded as ``Value``.
    @available(watchOS 9.0, *)
    func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value?
    
    /// Sets the value at `ubiquitousStoreKey` in `ubiquitousStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to update.
    /// - Parameter value: The value to encode.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` instance to update at `ubiquitousStoreKey`.
    @available(watchOS 9.0, *)
    func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore)
}

// MARK: - Default Implementation

/// Default store and container access built on ``PersistentKeyValueRepresentation/decode(storageObject:format:)`` and
/// ``PersistentKeyValueRepresentation/encode(_:format:)``.
///
/// Reads return `nil` when the stored object is absent or fails to decode. Writes remove the key when `encode`
/// returns `nil` and leave the store or container unchanged when `encode` throws or returns an object that is not a
/// property list. Property-list containers use ``PersistentKeyValueStorageFormat/propertyList``.
///
/// These defaults read the effective `UserDefaults` object without inspecting `UserDefaults.argumentDomain`, so they do
/// not coerce string launch arguments into typed values. Built-in representations implement these methods themselves
/// and keep that coercion.
extension PersistentKeyValueRepresentation {
    // MARK: Interfacing with Property List Array

    /// Decodes every element of `propertyListArray`, returning `nil` if any element fails to decode.
    public func get(from propertyListArray: [Any]) -> [Value]? {
        var values: [Value] = []

        values.reserveCapacity(propertyListArray.count)

        for object in propertyListArray {
            guard let value = decodedValue(from: object, format: .propertyList) else {
                return nil
            }

            values.append(value)
        }

        return values
    }

    /// Replaces `propertyListArray` with the encoded `values`, omitting elements whose `encode` returns `nil`.
    ///
    /// Leaves `propertyListArray` unchanged if encoding any element throws or returns an object that is not a property
    /// list.
    public func set(_ values: [Value], to propertyListArray: inout [Any]) {
        var objects: [Any] = []

        objects.reserveCapacity(values.count)

        for value in values {
            guard let object = encodedObject(for: value, format: .propertyList) else {
                return
            }

            if let object {
                objects.append(object)
            }
        }

        propertyListArray = objects
    }

    // MARK: Interfacing with Property List Dictionary

    /// Decodes the object at `dictionaryKey`, returning `nil` when it is absent or fails to decode.
    public func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value? {
        propertyListDictionary[dictionaryKey].flatMap {
            decodedValue(from: $0, format: .propertyList)
        }
    }

    /// Writes the encoded object, removes `dictionaryKey` when `encode` returns `nil`, and leaves
    /// `propertyListDictionary` unchanged when `encode` throws or returns an object that is not a property list.
    public func set(_ dictionaryKey: String, to value: Value, in propertyListDictionary: inout [String: Any]) {
        guard let object = encodedObject(for: value, format: .propertyList) else {
            return
        }

        if let object {
            propertyListDictionary[dictionaryKey] = object
        } else {
            propertyListDictionary.removeValue(forKey: dictionaryKey)
        }
    }

    // MARK: Interfacing with User Defaults

    /// Decodes the object returned by `object(forKey:)`, returning `nil` when it is absent or fails to decode.
    ///
    /// This default does not inspect `UserDefaults.argumentDomain`, so it does not coerce string launch arguments into
    /// typed values. Built-in representations implement this method themselves and keep that coercion.
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        userDefaults.object(forKey: userDefaultsKey).flatMap {
            decodedValue(from: $0, format: .userDefaults)
        }
    }

    /// Writes the encoded object, removes the key when `encode` returns `nil`, and leaves `userDefaults` unchanged
    /// when `encode` throws or returns an object that is not a property list.
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        guard let object = encodedObject(for: value, format: .userDefaults) else {
            return
        }

        if let object {
            userDefaults.set(object, forKey: userDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: userDefaultsKey)
        }
    }

    // MARK: Interfacing with Ubiquitous Key-Value Store

    /// Decodes the object returned by `object(forKey:)`, returning `nil` when it is absent or fails to decode.
    @available(watchOS 9.0, *)
    public func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey).flatMap {
            decodedValue(from: $0, format: .ubiquitousKeyValueStore)
        }
    }

    /// Writes the encoded object, removes the key when `encode` returns `nil`, and leaves `ubiquitousStore` unchanged
    /// when `encode` throws or returns an object that is not a property list.
    @available(watchOS 9.0, *)
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        guard let object = encodedObject(for: value, format: .ubiquitousKeyValueStore) else {
            return
        }

        if let object {
            ubiquitousStore.set(object, forKey: ubiquitousStoreKey)
        } else {
            ubiquitousStore.removeObject(forKey: ubiquitousStoreKey)
        }
    }

    // MARK: Private Instance Interface

    private func decodedValue(from object: Any, format: PersistentKeyValueStorageFormat) -> Value? {
        try? decode(storageObject: object, format: format)
    }

    // `try?` would flatten `Any??`, conflating a failed encoding with a request to remove the key. The outer `nil`
    // means `encode` threw or produced an object that is not a property list; `.some(nil)` means remove.
    private func encodedObject(for value: Value, format: PersistentKeyValueStorageFormat) -> Any?? {
        do {
            return storableEncoding(try encode(value, format: format))
        } catch {
            return nil
        }
    }
}

// MARK: - Container Conversion

extension PersistentKeyValueRepresentation {
    // MARK: Internal Instance Interface

    /// Returns the property-list array that stores `values`, or `nil` if any element fails to encode.
    ///
    /// Ordinary writes encode with ``set(_:to:)``, which reports a failure by leaving the array empty. An empty result
    /// for nonempty `values` is a failure unless a built-in representation omitted every value, such as an array of
    /// `nil` optionals, which ``omits(_:)`` decides without encoding the values again.
    @usableFromInline
    internal func propertyListArray(encoding values: [Value]) -> [Any]? {
        var objects: [Any] = []

        set(values, to: &objects)

        guard !objects.isEmpty || values.allSatisfy({ omits($0) }) else {
            return nil
        }

        return objects
    }

    /// Returns the property-list array that stores `values`, throwing if it cannot be encoded.
    ///
    /// A built-in representation encodes each element with its own checked conversion and rethrows the first error.
    /// Any other representation is encoded with ``set(_:to:)`` exactly as it implements it. That method receives an
    /// empty array, which it may assign or append to, and reports a failure by leaving it empty, so an empty result for
    /// nonempty `values` throws ``PersistentKeyValueConversionError/encodingFailed``.
    internal func checkedPropertyListArray(encoding values: [Value]) throws -> [Any] {
        if let builtIn = self as? any BuiltInContainerConversion {
            return try builtInPropertyListArray(encoding: values, with: builtIn)
        }

        var objects: [Any] = []

        set(values, to: &objects)

        guard !objects.isEmpty || values.isEmpty else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return objects
    }

    /// Returns the property-list dictionary that stores `values`, or `nil` if any value fails to encode.
    ///
    /// Ordinary writes encode each entry with ``set(_:to:in:)``, which reports a failure by leaving the entry absent.
    /// An absent entry is a failure unless a built-in representation omitted its value, such as a `nil` optional,
    /// which ``omits(_:)`` decides without encoding the value again.
    @usableFromInline
    internal func propertyListDictionary(encoding values: [String: Value]) -> [String: Any]? {
        var objects: [String: Any] = Dictionary(minimumCapacity: values.count)

        for (key, value) in values {
            set(key, to: value, in: &objects)

            guard objects[key] != nil || omits(value) else {
                return nil
            }
        }

        return objects
    }

    /// Returns the property-list dictionary that stores `values`, throwing if it cannot be encoded.
    ///
    /// A built-in representation encodes each value with its own checked conversion, omits values that encode to
    /// `nil`, and rethrows the first error. Any other representation is encoded with ``set(_:to:in:)`` exactly as it
    /// implements it. That method receives a dictionary that does not yet contain the entry's key and reports a
    /// failure by leaving it absent, so an absent entry throws ``PersistentKeyValueConversionError/encodingFailed``.
    internal func checkedPropertyListDictionary(encoding values: [String: Value]) throws -> [String: Any] {
        if let builtIn = self as? any BuiltInContainerConversion {
            return try builtInPropertyListDictionary(encoding: values, with: builtIn)
        }

        var objects: [String: Any] = Dictionary(minimumCapacity: values.count)

        for (key, value) in values {
            set(key, to: value, in: &objects)

            guard objects[key] != nil else {
                throw PersistentKeyValueConversionError.encodingFailed
            }
        }

        return objects
    }

    /// Returns the values stored in `propertyListArray`, throwing if it cannot be decoded.
    ///
    /// A built-in representation decodes each element with its own checked conversion, so a nested dictionary fails
    /// instead of omitting an entry, and rethrows the first error in input order. Any other representation is decoded
    /// with ``get(from:)`` exactly as it implements it, and a `nil` result throws
    /// ``PersistentKeyValueConversionError/invalidStorageValue``.
    internal func checkedValues(decoding propertyListArray: [Any]) throws -> [Value] {
        if let builtIn = self as? any BuiltInContainerConversion {
            return try builtInValues(decoding: propertyListArray, with: builtIn)
        }

        return try values(readingArray: propertyListArray)
    }

    /// Returns the values stored in `propertyListArray`, each converted with `convert`, throwing if any element cannot
    /// be decoded or converted.
    ///
    /// A built-in representation, including a built-in scalar such as `Int`, finishes decoding and converting each
    /// element before it reads the next, so the first error in input order is rethrown even when it comes from
    /// `convert`, such as a proxy representation's conversion of its decoded proxy. Any other representation is
    /// decoded with ``get(from:)`` exactly as it implements it, so a `nil` result throws
    /// ``PersistentKeyValueConversionError/invalidStorageValue`` before any value is converted.
    internal func checkedValues<Element>(
        decoding propertyListArray: [Any],
        converting convert: (Value) throws -> Element
    ) throws -> [Element] {
        if let builtIn = self as? any BuiltInContainerConversion {
            return try builtInValues(decoding: propertyListArray, converting: convert, with: builtIn)
        }

        // A built-in scalar's array read decodes each element exactly as its checked conversion does, so decoding
        // one element at a time produces the same values while reporting the first error in input order.
        if self is any BuiltInScalarConversion {
            return try propertyListArray.map {
                try convert(decode(storageObject: $0, format: .propertyList))
            }
        }

        return try values(readingArray: propertyListArray).map(convert)
    }

    /// Returns the values stored in `propertyListDictionary`, throwing if any entry cannot be decoded.
    ///
    /// A built-in representation decodes each entry with its own checked conversion and rethrows the first error. Any
    /// other representation is decoded with ``get(_:from:)`` exactly as it implements it, and a `nil` result throws
    /// ``PersistentKeyValueConversionError/invalidStorageValue``.
    internal func checkedDictionary(decoding propertyListDictionary: [String: Any]) throws -> [String: Value] {
        if let builtIn = self as? any BuiltInContainerConversion {
            return try builtInDictionary(decoding: propertyListDictionary, with: builtIn)
        }

        var values: [String: Value] = Dictionary(minimumCapacity: propertyListDictionary.count)

        for key in propertyListDictionary.keys {
            guard let value = get(key, from: propertyListDictionary) else {
                throw PersistentKeyValueConversionError.invalidStorageValue
            }

            values[key] = value
        }

        return values
    }

    /// Returns the entries of `propertyListDictionary` that decode with ``get(_:from:)``, omitting entries that fail
    /// to decode.
    ///
    /// Dictionary entries are independent, so one unreadable entry (such as an enum case written by a newer app
    /// version) does not hide the others. Writing the result back therefore keeps every readable entry.
    @usableFromInline
    internal func dictionary(decoding propertyListDictionary: [String: Any]) -> [String: Value] {
        var values: [String: Value] = Dictionary(minimumCapacity: propertyListDictionary.count)

        for key in propertyListDictionary.keys {
            values[key] = get(key, from: propertyListDictionary)
        }

        return values
    }

    /// Returns whether an ordinary container write omits `value` instead of storing it.
    ///
    /// Only a built-in representation omits a value; any other representation reports a failure by leaving it out.
    /// This method invokes no encoding hook, so it does not re-encode a failed value: retrying a failed write at
    /// every level of a recursive value takes time exponential in its depth.
    internal func omits(_ value: Value) -> Bool {
        guard let omitting = self as? any BuiltInValueOmission else {
            return false
        }

        return builtInOmits(value, with: omitting)
    }

    /// Whether an ordinary container write omits any value of this representation.
    internal var omitsValues: Bool {
        (self as? any BuiltInValueOmission)?.builtInOmitsValues ?? false
    }

    // MARK: Private Instance Interface

    // `builtIn` is `self`, so its `Value` is this representation's `Value`; the cast only restores the static type.

    private func builtInPropertyListArray<BuiltIn: BuiltInContainerConversion>(
        encoding values: [Value],
        with builtIn: BuiltIn
    ) throws -> [Any] {
        try builtIn.builtInPropertyListArray(encoding: values as! [BuiltIn.Value])
    }

    private func builtInPropertyListDictionary<BuiltIn: BuiltInContainerConversion>(
        encoding values: [String: Value],
        with builtIn: BuiltIn
    ) throws -> [String: Any] {
        try builtIn.builtInPropertyListDictionary(encoding: values as! [String: BuiltIn.Value])
    }

    private func builtInValues<BuiltIn: BuiltInContainerConversion>(
        decoding propertyListArray: [Any],
        with builtIn: BuiltIn
    ) throws -> [Value] {
        try builtIn.builtInValues(decoding: propertyListArray) {
            $0
        } as! [Value]
    }

    private func builtInValues<BuiltIn: BuiltInContainerConversion, Element>(
        decoding propertyListArray: [Any],
        converting convert: (Value) throws -> Element,
        with builtIn: BuiltIn
    ) throws -> [Element] {
        try builtIn.builtInValues(decoding: propertyListArray) {
            try convert($0 as! Value)
        }
    }

    private func builtInOmits<BuiltIn: BuiltInValueOmission>(_ value: Value, with builtIn: BuiltIn) -> Bool {
        builtIn.builtInOmits(value as! BuiltIn.Value)
    }

    private func builtInDictionary<BuiltIn: BuiltInContainerConversion>(
        decoding propertyListDictionary: [String: Any],
        with builtIn: BuiltIn
    ) throws -> [String: Value] {
        try builtIn.builtInDictionary(decoding: propertyListDictionary) as! [String: Value]
    }

    /// Decodes `propertyListArray` with ``get(from:)``, throwing
    /// ``PersistentKeyValueConversionError/invalidStorageValue`` when it returns `nil`.
    private func values(readingArray propertyListArray: [Any]) throws -> [Value] {
        guard let values = get(from: propertyListArray) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return values
    }
}

// MARK: - Built-In Container Conversion Definition

/// A representation defined by this package whose checked container conversion does not go through its public
/// container methods.
///
/// Built-in container methods are ordinary reads and writes: for example, a nested dictionary read omits entries that
/// fail to decode. Checked conversion, which migration and registration use, must instead fail. A built-in
/// representation therefore converts its elements through checked conversion directly, recursing into the checked
/// conversion of its base or proxy representation, and converts an array one element at a time so that it reports the
/// first error in input order. A representation defined outside this package does not conform, so checked conversion
/// calls its container methods exactly as it implements them, including the protocol's default implementations.
internal protocol BuiltInContainerConversion: PersistentKeyValueRepresentation {
    /// Returns the property-list array that stores `values`, throwing the first error.
    func builtInPropertyListArray(encoding values: [Value]) throws -> [Any]

    /// Returns the property-list dictionary that stores `values`, throwing the first error.
    func builtInPropertyListDictionary(encoding values: [String: Value]) throws -> [String: Any]

    /// Returns the values stored in `propertyListArray`, each converted with `convert`, throwing the first error in
    /// input order.
    ///
    /// Each element is decoded and passed to `convert` before the next element is read.
    func builtInValues<Element>(
        decoding propertyListArray: [Any],
        converting convert: (Value) throws -> Element
    ) throws -> [Element]

    /// Returns the values stored in `propertyListDictionary`, throwing the first error.
    func builtInDictionary(decoding propertyListDictionary: [String: Any]) throws -> [String: Value]
}

// MARK: - Built-In Scalar Conversion Definition

/// A representation of a built-in scalar primitive, such as `Int` or `URL`, whose container methods convert each
/// element exactly as its checked conversion does.
///
/// Checked conversion uses these container methods, except when a built-in proxy or optional representation also
/// converts each element: it then decodes one element at a time so that it reports the first error in input order.
internal protocol BuiltInScalarConversion: PersistentKeyValueRepresentation {}

// MARK: - Built-In Value Omission Definition

/// A representation defined by this package whose ordinary container writes can omit a value instead of storing it.
///
/// ``OptionalPersistentKeyValueRepresentation`` omits `nil`, and a built-in proxy representation omits a value whose
/// proxy its `Proxy` representation omits. An ordinary write reports a failure by leaving an array empty or a
/// dictionary entry absent, which is also what omitting every value produces, so the write asks this protocol which
/// happened instead of encoding the values again. Its methods invoke no encoding hook. The one exception is a proxy
/// whose `Proxy` representation omits values, such as a proxy to an optional: deciding whether it omits a value
/// converts that value to its proxy again.
internal protocol BuiltInValueOmission: PersistentKeyValueRepresentation {
    /// Whether an ordinary container write omits any value of this representation.
    var builtInOmitsValues: Bool { get }

    /// Returns whether an ordinary container write omits `value` instead of storing it.
    func builtInOmits(_ value: Value) -> Bool
}

/// The storage format used to encode or decode a persistent value.
public enum PersistentKeyValueStorageFormat: Sendable {
    /// A property-list container such as an array or dictionary.
    case propertyList

    /// An `NSUbiquitousKeyValueStore` domain.
    case ubiquitousKeyValueStore

    /// A `UserDefaults` persistent domain.
    case userDefaults
}

/// Errors thrown by built-in representations when converting between a Swift value and a stored object.
public enum PersistentKeyValueConversionError: Error, Equatable, Sendable {
    /// The stored object has an unexpected runtime type, is not a valid property list, or exceeds the target store's
    /// size limit.
    case invalidStorageValue

    /// The stored or proxied value could not be converted into the target Swift type.
    case invalidValue

    /// The Swift value could not be converted into its proxy or storage representation.
    case encodingFailed
}

/// Returns `object` wrapped for storage, or `nil` when it is not a property list that a store accepts.
///
/// Foundation stores raise an Objective-C exception for non-property-list objects, so the default write paths treat
/// such an object as a failed encoding.
internal func storableEncoding(_ object: Any?) -> Any?? {
    guard let object else {
        return .some(nil)
    }

    guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
        return nil
    }

    return .some(object)
}

internal func checkedStorageValue<Value>(from object: Any, as type: Value.Type = Value.self) throws -> Value {
    guard let value = object as? Value else {
        throw PersistentKeyValueConversionError.invalidStorageValue
    }
    return value
}

internal func decodeStorageValue<Key: PersistentKeyProtocol>(
    for key: Key,
    object: Any,
    format: PersistentKeyValueStorageFormat
) throws -> Key.Value {
    try key.representation.decode(storageObject: object, format: format)
}

internal func encodeStorageRepresentation<Value, Representation: PersistentKeyValueRepresentation>(
    _ representation: Representation,
    value: Value,
    format: PersistentKeyValueStorageFormat
) throws -> Any?
where Representation.Value == Value {
    let object = try representation.encode(value, format: format)
    if let object {
        _ = try representation.decode(storageObject: object, format: format)
    }
    return object
}

internal func encodeStorageValue<Key: PersistentKeyProtocol>(
    _ value: Key.Value,
    for key: Key,
    format: PersistentKeyValueStorageFormat
) throws -> Any? {
    try encodeStorageRepresentation(key.representation, value: value, format: format)
}
