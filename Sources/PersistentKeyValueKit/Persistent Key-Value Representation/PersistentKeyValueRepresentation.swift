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
///
/// An object that ``encode(_:format:)`` returns or a `set` method writes is handed over to the caller: do not mutate it
/// afterward, including a mutable string or data buffer, a mutable dictionary key, or a container. As a defense, the
/// default `set` methods and the conversion of `Array` and `Dictionary` values copy the mutable containers and leaf
/// values that they accept, except dictionary keys. A `set` method that forwards to another `set` method, as the
/// container methods of ``OptionalPersistentKeyValueRepresentation``, ``ProxyPersistentKeyValueRepresentation``, and
/// ``PrimitivePersistentKeyValueRepresentation`` do, writes the objects that method writes without copying them.
/// Behavior is unspecified if a representation mutates an object after handing it over.
///
/// Conversion can run more than once for the same value, and ordinary `get` and `set` stay non-throwing. In a target
/// whose default isolation is `MainActor`, the conversion witnesses must be usable from nonisolated code, where a key
/// constructs its representation and migration calls it. Declaring the conformance's type and extension `nonisolated`
/// does that, and individually `nonisolated` witnesses can preserve the rest of the type's isolation.
public protocol PersistentKeyValueRepresentation<Value>: Sendable {
    // MARK: Associated Types
    
    /// The type of value that is represented in a ``PersistentKeyValueStore``.
    associatedtype Value

    /// Decodes a value from a stored object for the given storage format.
    ///
    /// Callers such as migration write validation may invoke conversion more than once for the same value; do not
    /// rely on a specific invocation count.
    ///
    /// Accept every object that this representation's setter or ``encode(_:format:)`` writes, in the immutable
    /// Foundation form that a store returns, because migration validates an encoded object by decoding an immutable
    /// copy of it, and `UserDefaults` and `NSUbiquitousKeyValueStore` can return a widened integer to another process
    /// or a later launch. A decoder that requires `NSMutableArray` rejects its own encoder's output during migration.
    ///
    /// - Parameter storageObject: The stored object read from the backing store or property-list container.
    /// - Parameter format: The storage format of `storageObject`.
    /// - Returns: The decoded value.
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value

    /// Encodes a value into a stored object for the given storage format.
    ///
    /// Returning `nil` removes the key from a store. The default container methods omit such a value from a
    /// property-list collection, but an omission that leaves a dictionary entry absent or a nonempty array empty fails
    /// the write; see ``set(_:to:in:)-91w4n`` and ``set(_:to:)``. Callers such as migration write validation may
    /// invoke conversion more than once for the same value; do not rely on a specific invocation count. Do not mutate
    /// the returned object, or any object it contains, after returning it.
    ///
    /// Migration to a `UserDefaults` or `NSUbiquitousKeyValueStore` destination removes the destination entry only
    /// when this method returns `nil` for the key's top-level value and that value is `nil` at an actual `Optional`
    /// layer. If it returns `nil` for any other top-level value, the item fails at
    /// ``PersistentKeyMigrationReport/FailureStage/prepare`` with
    /// ``PersistentKeyValueConversionError/encodingFailed``, writes neither entry, and the other items in the batch
    /// proceed independently. This does not cover a `nil` element inside a collection, such as a custom element
    /// encoder that returns `nil` for one array element, which the collection write omits, so a move can succeed with
    /// fewer elements.
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
    /// them from migrated values too, including when an optional, proxy, or nested collection representation reaches
    /// it. Checked migration can therefore succeed with fewer elements, and remove the source of a move, when this
    /// method filters unreadable elements.
    ///
    /// - Parameter propertyListArray: The array to decode values from.
    /// - Returns: The decoded values, or `nil` if any element cannot be decoded as ``Value``.
    func get(from propertyListArray: [Any]) -> [Value]?

    /// Writes the encoded representations of `values` into `propertyListArray`.
    ///
    /// Array writes, registration, and migration call this method with an empty `propertyListArray`, and an
    /// implementation may only assign the encoded array to it or append the encoded elements to it. Build the encoded
    /// array separately and assign or append it only after every value encodes, because the package stores a nonempty
    /// result as written. The result is the stored form of `values` and need not contain each element's own encoding.
    /// If any value fails to encode, leave `propertyListArray` empty. Callers rely on this to keep the stored collection when one of its elements
    /// cannot be encoded, so an empty result for nonempty `values` counts as a failure, even if every value encodes to
    /// `nil`. So does a result that is not a property list that `UserDefaults` and `NSUbiquitousKeyValueStore` accept,
    /// such as one that contains the UIDs in a keyed archive's property list. Do not mutate the objects written to
    /// `propertyListArray` after this method returns.
    ///
    /// - Parameter values: The values to encode into `propertyListArray`.
    /// - Parameter propertyListArray: The array to write the encoded values into.
    func set(_ values: [Value], to propertyListArray: inout [Any])
    
    // MARK: Interfacing with Property List Dictionary

    /// Decodes the value at `dictionaryKey` in `propertyListDictionary`, if present and representable as ``Value``.
    ///
    /// Dictionary reads decode a stored entry with this method, so it must accept the objects that
    /// ``set(_:to:in:)-91w4n`` writes. Ordinary dictionary reads omit an entry for which this method returns `nil`.
    /// Checked conversion, which migration and `UserDefaults.register(_:)` use, also calls this method for
    /// representations defined outside this package and fails instead: checked dictionary decoding throws when this
    /// method returns `nil`, but accepts a value from which it has already omitted nested entries.
    ///
    /// - Parameter dictionaryKey: The key to look up.
    /// - Parameter propertyListDictionary: The dictionary to read from.
    /// - Returns: The decoded value at `dictionaryKey` in `propertyListDictionary`, or `nil` if it is absent or cannot
    ///   be decoded as ``Value``.
    func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value?

    /// Sets the value at `dictionaryKey` in `propertyListDictionary`.
    ///
    /// Write only the entry for `dictionaryKey`; do not read, modify, add, or remove other entries. If `value` fails to
    /// encode, leave `propertyListDictionary` unchanged; if it encodes to `nil`, remove `dictionaryKey`. Dictionary
    /// writes, registration, and migration call this method for a `dictionaryKey` that `propertyListDictionary` does
    /// not yet contain, and rely on this to keep the stored dictionary when one of its values cannot be encoded, so an
    /// absent entry counts as a failure, even if the value encodes to `nil`. So does an entry that is not a property
    /// list that `UserDefaults` and `NSUbiquitousKeyValueStore` accept, such as one that contains the UIDs in a keyed
    /// archive's property list. Do not mutate the object written to the entry after this method returns.
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
    /// Do not mutate the object written to `userDefaults` after this method returns.
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
    /// Do not mutate the object written to `ubiquitousStore` after this method returns.
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
/// A property list contains only strings, numbers, dates, data, arrays, and dictionaries with string keys, which are
/// the objects that `UserDefaults` and `NSUbiquitousKeyValueStore` store. Binary property-list serialization also
/// accepts the UIDs in a keyed archive's property list, but these writes reject them (store such an archive as
/// `Data`), along with `NSNull`, `URL` objects, non-string dictionary keys, and containers that contain themselves.
/// As a defense, writes keep immutable copies of the mutable containers and leaf values in the object that `encode`
/// returns, but not of every mutable object, such as a dictionary key. A representation must still not mutate that
/// object, or any object it contains, after `encode` returns.
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

    /// Returns the property-list array that an ordinary write stores for `values`, or `nil` if any element fails to
    /// encode.
    ///
    /// A built-in representation that can omit values, such as `nil` optionals, converts each value once and tells an
    /// omitted value from a failed one as it converts it. Any other representation is encoded with ``set(_:to:)``,
    /// which reports a failure by leaving the array empty, so an empty result for nonempty `values` is a failure. A
    /// result that a representation defined outside this package writes also fails unless it is a property list that
    /// a store accepts.
    @usableFromInline
    internal func propertyListArray(encoding values: [Value]) -> [Any]? {
        if self is any BuiltInPrimitiveConversion {
            return propertyListArray(setting: values, validating: false)
        }

        if let omitting = self as? any BuiltInValueOmission {
            return builtInOrdinaryPropertyListArray(encoding: values, with: omitting)
        }

        return propertyListArray(setting: values, validating: true)
    }

    /// Returns the property-list arrays that ordinary writes store for each of `arrays`, or `nil` if any element fails
    /// to encode.
    ///
    /// This encodes each array as ``propertyListArray(encoding:)`` does, but decides only once how this representation
    /// writes them, because that decision costs as much as writing a small array.
    internal func propertyListArrays(encoding arrays: [[Value]]) -> [Any]? {
        let encode: ([Value]) -> [Any]? = if self is any BuiltInPrimitiveConversion {
            { propertyListArray(setting: $0, validating: false) }
        } else if let omitting = self as? any BuiltInValueOmission {
            { builtInOrdinaryPropertyListArray(encoding: $0, with: omitting) }
        } else {
            { propertyListArray(setting: $0, validating: true) }
        }
        var objects: [Any] = []

        objects.reserveCapacity(arrays.count)

        for values in arrays {
            guard let object = encode(values) else {
                return nil
            }

            objects.append(object)
        }

        return objects
    }

    /// Returns the property-list array that stores `values`, throwing if it cannot be encoded.
    ///
    /// A built-in representation encodes each element with its own checked conversion and rethrows the first error.
    /// Any other representation is encoded with ``set(_:to:)`` exactly as it implements it. That method receives an
    /// empty array, which it may assign or append to, and reports a failure by leaving it empty, so an empty result for
    /// nonempty `values` throws ``PersistentKeyValueConversionError/encodingFailed``. So does a result that a
    /// representation defined outside this package writes, unless it is a property list that a store accepts.
    internal func checkedPropertyListArray(encoding values: [Value]) throws -> [Any] {
        if let builtIn = self as? any BuiltInContainerConversion {
            return try builtInPropertyListArray(encoding: values, with: builtIn)
        }

        let validating = !(self is any BuiltInPrimitiveConversion)

        guard let objects = propertyListArray(setting: values, validating: validating) else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return objects
    }

    /// Returns the property-list dictionary that an ordinary write stores for `values`, or `nil` if any value fails
    /// to encode.
    ///
    /// A built-in representation that can omit values, such as `nil` optionals, converts each value once and tells an
    /// omitted value from a failed one as it converts it. Any other representation encodes each entry with
    /// ``set(_:to:in:)``, which reports a failure by leaving the entry absent, so an absent entry is a failure. An
    /// entry that a representation defined outside this package writes, or changes while writing a later entry, also
    /// fails unless it is a property list that a store accepts. Either way, the write stops at the first value that
    /// fails to encode.
    @usableFromInline
    internal func propertyListDictionary(encoding values: [String: Value]) -> [String: Any]? {
        if self is any BuiltInPrimitiveConversion {
            return propertyListDictionary(setting: values, validating: false)
        }

        if let omitting = self as? any BuiltInValueOmission {
            return builtInOrdinaryPropertyListDictionary(encoding: values, with: omitting)
        }

        return propertyListDictionary(setting: values, validating: true)
    }

    /// Returns the property-list dictionaries that ordinary writes store for each of `dictionaries`, or `nil` if any
    /// value fails to encode.
    ///
    /// This encodes each dictionary as ``propertyListDictionary(encoding:)`` does, but decides only once how this
    /// representation writes them, because that decision costs as much as writing a small dictionary.
    @usableFromInline
    internal func propertyListDictionaries(encoding dictionaries: [[String: Value]]) -> [Any]? {
        let encode: ([String: Value]) -> [String: Any]? = if self is any BuiltInPrimitiveConversion {
            { propertyListDictionary(setting: $0, validating: false) }
        } else if let omitting = self as? any BuiltInValueOmission {
            { builtInOrdinaryPropertyListDictionary(encoding: $0, with: omitting) }
        } else {
            { propertyListDictionary(setting: $0, validating: true) }
        }
        var objects: [Any] = []

        objects.reserveCapacity(dictionaries.count)

        for values in dictionaries {
            guard let object = encode(values) else {
                return nil
            }

            objects.append(object)
        }

        return objects
    }

    /// Writes each entry of `values` with `write`, stopping at the first value that fails to encode.
    ///
    /// If `write` calls a dictionary container method defined outside this package, the completed dictionary also
    /// fails unless every entry is a property list that a store accepts, as ``isStorableDictionary(_:)`` describes.
    internal func propertyListDictionary(
        encoding values: [String: Value],
        with write: OrdinaryDictionaryEntryWriter<Value>
    ) -> [String: Any]? {
        var objects: [String: Any] = Dictionary(minimumCapacity: values.count)

        for (key, value) in values {
            guard write(key, value, &objects) else {
                return nil
            }
        }

        guard !write.requiresCompletedDictionaryValidation || isStorableDictionary(&objects) else {
            return nil
        }

        return objects
    }

    /// Returns a function that writes the entry an ordinary dictionary write stores for a value, reporting whether the
    /// value encoded.
    ///
    /// The function receives a key that the dictionary does not yet contain. It returns `false` if the value fails to
    /// encode, and `true` if it wrote the entry or omitted the value, leaving the key absent. A built-in representation
    /// that can omit values, such as `nil` optionals, converts the value once and passes the result inward through
    /// each representation it wraps, so a failure at any layer stops the write before the next value is converted.
    /// Any other representation writes the entry with ``set(_:to:in:)``, which reports a failure by leaving the entry
    /// absent; an entry that a representation defined outside this package writes also fails unless it is a property
    /// list that a store accepts, and such a writer requires validation of the completed dictionary.
    ///
    /// Calling the function costs more than writing the entry directly, so a built-in representation writes through
    /// it only when the representation it wraps can omit values.
    internal func ordinaryDictionaryEntryWriter() -> OrdinaryDictionaryEntryWriter<Value> {
        if let omitting = self as? any BuiltInValueOmission {
            return builtInOrdinaryDictionaryEntryWriter(with: omitting)
        }

        let validating = !(self is any BuiltInPrimitiveConversion)

        return OrdinaryDictionaryEntryWriter(requiresCompletedDictionaryValidation: validating) { key, value, objects in
            set(key, to: value, in: &objects)

            return isStorableEntry(at: key, in: &objects, validating: validating)
        }
    }

    /// Returns the property-list dictionary that stores `values`, throwing if it cannot be encoded.
    ///
    /// A built-in representation encodes each value with its own checked conversion, omits values that encode to
    /// `nil`, and rethrows the first error. Any other representation is encoded with ``set(_:to:in:)`` exactly as it
    /// implements it. That method receives a dictionary that does not yet contain the entry's key and reports a
    /// failure by leaving it absent, so an absent entry throws ``PersistentKeyValueConversionError/encodingFailed``.
    /// So does an entry that a representation defined outside this package writes, or changes while writing a later
    /// entry, unless it is a property list that a store accepts.
    internal func checkedPropertyListDictionary(encoding values: [String: Value]) throws -> [String: Any] {
        if let builtIn = self as? any BuiltInContainerConversion {
            return try builtInPropertyListDictionary(encoding: values, with: builtIn)
        }

        let validating = !(self is any BuiltInPrimitiveConversion)

        guard let objects = propertyListDictionary(setting: values, validating: validating) else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return objects
    }

    /// Returns the values stored in `propertyListArray`, throwing if it cannot be decoded.
    ///
    /// A built-in representation decodes each element with its own checked conversion, so a nested dictionary fails
    /// instead of omitting an entry, and rethrows the first error in input order when every representation in its
    /// conversion chain is built in and converts only built-in primitive types. Any other representation, including
    /// ``PrimitivePersistentKeyValueRepresentation`` for a primitive type defined outside this package, is decoded with
    /// ``get(from:)`` exactly as it implements it, and a `nil` result throws
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
    /// When every representation in the conversion chain is built in and converts only built-in primitive types, such
    /// as `Int`, each element is decoded and converted before the next is read, so the first error in input order is
    /// rethrown even when it comes from `convert`, such as a proxy representation's conversion of its decoded proxy.
    /// Any other representation, including one that a built-in proxy representation wraps and
    /// ``PrimitivePersistentKeyValueRepresentation`` for a primitive type defined outside this package, is decoded with
    /// ``get(from:)`` exactly as it implements it, so a `nil` result throws
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
    /// version) does not hide the others. Writing the result back keeps every readable entry and deletes the
    /// unreadable ones.
    @usableFromInline
    internal func dictionary(decoding propertyListDictionary: [String: Any]) -> [String: Value] {
        var values: [String: Value] = Dictionary(minimumCapacity: propertyListDictionary.count)

        for key in propertyListDictionary.keys {
            values[key] = get(key, from: propertyListDictionary)
        }

        return values
    }

    /// Encodes `values` with ``set(_:to:)``, which reports a failure by leaving the array empty.
    ///
    /// If `validating`, a result that is not a property list that a store accepts is also a failure, and each element
    /// is replaced with its snapshot, as ``storablePropertyList(_:)`` describes.
    internal func propertyListArray(setting values: [Value], validating: Bool) -> [Any]? {
        var objects: [Any] = []

        set(values, to: &objects)

        guard !objects.isEmpty || values.isEmpty else {
            return nil
        }

        if validating {
            guard let copies = storableCopies(of: objects) else {
                return nil
            }

            for (index, copy) in copies {
                objects[index] = copy
            }
        }

        return objects
    }

    /// Encodes each entry of `values` with ``set(_:to:in:)``, which reports a failure by leaving the entry absent.
    ///
    /// If `validating`, an entry that is not a property list that a store accepts is also a failure, whether
    /// ``set(_:to:in:)`` wrote it for that entry's value or changed it while writing a later one, and each entry is
    /// replaced with its snapshot, as ``storablePropertyList(_:)`` describes.
    internal func propertyListDictionary(setting values: [String: Value], validating: Bool) -> [String: Any]? {
        var objects: [String: Any] = Dictionary(minimumCapacity: values.count)

        for (key, value) in values {
            set(key, to: value, in: &objects)

            guard isStorableEntry(at: key, in: &objects, validating: validating) else {
                return nil
            }
        }

        guard !validating || isStorableDictionary(&objects) else {
            return nil
        }

        return objects
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

    // Ordinary writes are a hot path, and `as!` casts a collection element by element, so these reinterpret it
    // after checking that the types are identical.

    private func builtInOrdinaryPropertyListArray<BuiltIn: BuiltInValueOmission>(
        encoding values: [Value],
        with builtIn: BuiltIn
    ) -> [Any]? {
        precondition(BuiltIn.Value.self == Value.self)

        return builtIn.builtInOrdinaryPropertyListArray(encoding: unsafeBitCast(values, to: [BuiltIn.Value].self))
    }

    private func builtInOrdinaryPropertyListDictionary<BuiltIn: BuiltInValueOmission>(
        encoding values: [String: Value],
        with builtIn: BuiltIn
    ) -> [String: Any]? {
        precondition(BuiltIn.Value.self == Value.self)

        return builtIn.builtInOrdinaryPropertyListDictionary(
            encoding: unsafeBitCast(values, to: [String: BuiltIn.Value].self)
        )
    }

    private func builtInOrdinaryDictionaryEntryWriter<BuiltIn: BuiltInValueOmission>(
        with builtIn: BuiltIn
    ) -> OrdinaryDictionaryEntryWriter<Value> {
        precondition(BuiltIn.Value.self == Value.self)

        let write = builtIn.builtInOrdinaryDictionaryEntryWriter()

        return OrdinaryDictionaryEntryWriter(
            requiresCompletedDictionaryValidation: write.requiresCompletedDictionaryValidation
        ) { key, value, objects in
            write(key, unsafeBitCast(value, to: BuiltIn.Value.self), &objects)
        }
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
/// conversion of its base or proxy representation. Checked decoding converts an array one element at a time, so a
/// conversion chain of these representations reports the first error in input order. A chain that reaches a
/// representation defined outside this package, or ``PrimitivePersistentKeyValueRepresentation`` for a primitive type
/// defined outside it, does not: that representation reads the whole array first, so its error is reported before an
/// outer proxy representation converts an earlier element. Checked encoding makes no
/// input-order promise: a proxy representation converts every value to its proxy before encoding any, so a later
/// value's failed conversion can be reported instead of an earlier value's encoding error. A representation defined
/// outside this package does not conform, so checked conversion calls its container methods exactly as it implements
/// them, including the protocol's default implementations.
internal protocol BuiltInContainerConversion: PersistentKeyValueRepresentation {
    /// Returns the property-list array that stores `values`, throwing the first error.
    func builtInPropertyListArray(encoding values: [Value]) throws -> [Any]

    /// Returns the property-list dictionary that stores `values`, throwing the first error.
    func builtInPropertyListDictionary(encoding values: [String: Value]) throws -> [String: Any]

    /// Returns the values stored in `propertyListArray`, each converted with `convert`, throwing the first error.
    ///
    /// Each element is decoded and passed to `convert` before the next element is read, unless the conversion chain
    /// reaches a representation defined outside this package or ``PrimitivePersistentKeyValueRepresentation`` for a
    /// primitive type defined outside it, which reads the whole array first.
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

// MARK: - Built-In Primitive Conversion Definition

/// A representation of a built-in primitive type, such as `Int` or `[String: Int]`, whose container methods write only
/// property lists that a store accepts.
///
/// Container methods implemented outside this package can write any object, including one that binary property-list
/// validation accepts but a store rejects, such as the UIDs in a keyed archive's property list, so ordinary writes
/// validate what such methods write before a store receives it, and keep immutable copies of its mutable containers
/// and leaf values so that a later conversion cannot change them. A conforming representation's container methods
/// write only such property lists, or encode the elements of a container through the ordinary writes of their own
/// representation, which validate and copy what they write, so ordinary writes skip that validation. A built-in proxy
/// or optional representation does not conform; it writes through ``BuiltInValueOmission`` instead.
internal protocol BuiltInPrimitiveConversion: PersistentKeyValueRepresentation {}

// MARK: - Built-In Value Omission Definition

/// A representation defined by this package whose ordinary container writes can omit a value instead of storing it.
///
/// ``OptionalPersistentKeyValueRepresentation`` omits `nil`, and a built-in proxy representation omits a value whose
/// proxy its `Proxy` representation omits. The public container methods report a failure by leaving an array empty or
/// a dictionary entry absent, which is also what omitting every value produces. Ordinary container writes therefore
/// encode through this protocol, whose methods convert each value once and decide whether it was omitted from that
/// conversion. Converting a value again to decide would convert a recursive value's whole subtree again at every
/// level, which takes time exponential in its depth. A dictionary write also converts each value through every layer
/// before converting the next, so the first value that fails to encode stops the write.
internal protocol BuiltInValueOmission: PersistentKeyValueRepresentation {
    /// Returns the property-list array that an ordinary write stores for `values`, or `nil` if any value fails to
    /// encode.
    func builtInOrdinaryPropertyListArray(encoding values: [Value]) -> [Any]?

    /// Returns the property-list dictionary that an ordinary write stores for `values`, or `nil` if any value fails
    /// to encode, stopping at the first such value.
    func builtInOrdinaryPropertyListDictionary(encoding values: [String: Value]) -> [String: Any]?

    /// Returns a function that writes the entry an ordinary dictionary write stores for a value, as
    /// ``PersistentKeyValueRepresentation/ordinaryDictionaryEntryWriter()`` describes.
    func builtInOrdinaryDictionaryEntryWriter() -> OrdinaryDictionaryEntryWriter<Value>
}

/// A callable writer of the entry that an ordinary dictionary write stores for a value.
///
/// See ``PersistentKeyValueRepresentation/ordinaryDictionaryEntryWriter()``.
internal struct OrdinaryDictionaryEntryWriter<Value> {
    /// Whether the writer calls a dictionary container method defined outside this package, which can change an entry
    /// that an earlier call wrote, so a write must validate the completed dictionary with ``isStorableDictionary(_:)``.
    let requiresCompletedDictionaryValidation: Bool

    private let write: (_ key: String, _ value: Value, _ objects: inout [String: Any]) -> Bool

    // MARK: Initialization

    init(
        requiresCompletedDictionaryValidation: Bool,
        write: @escaping (_ key: String, _ value: Value, _ objects: inout [String: Any]) -> Bool
    ) {
        self.requiresCompletedDictionaryValidation = requiresCompletedDictionaryValidation
        self.write = write
    }

    // MARK: Instance Interface

    /// Writes the entry for `value` at `key`, which `objects` does not yet contain, and returns whether `value`
    /// encoded.
    func callAsFunction(_ key: String, _ value: Value, _ objects: inout [String: Any]) -> Bool {
        write(key, value, &objects)
    }
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
///
/// `URL` archive encoding and decoding can throw Foundation errors instead, and
/// ``CodablePersistentKeyValueRepresentation`` rethrows the errors of its `Encoder` and `Decoder`.
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
/// such an object as a failed encoding. The wrapped object is `object` itself if it is a Swift `String`, `Int`,
/// `Double`, `Bool`, `Data`, or `Date` value, which validation need not bridge, and otherwise the snapshot that
/// ``storablePropertyList(_:)`` returns, so a store, or a later validation of a collection that holds it, does not
/// bridge it again. Either way, a later conversion that changes a mutable object that `object` is or holds does not
/// change what is stored, except a mutable dictionary key, which the snapshot may share.
internal func storableEncoding(_ object: Any?) -> Any?? {
    guard let object else {
        return .some(nil)
    }

    guard !isSwiftPropertyListLeaf(object) else {
        return .some(object)
    }

    guard let storableObject = storablePropertyList(object) else {
        return nil
    }

    return .some(storableObject)
}

/// Returns whether `object` is a property list that `UserDefaults` and `NSUbiquitousKeyValueStore` accept.
///
/// See ``storablePropertyList(_:)``.
internal func isStorablePropertyList(_ object: Any) -> Bool {
    storableSnapshot(of: object) != nil
}

/// Returns the snapshots that are copies of the elements of `objects`, an array that an array container method wrote,
/// with their indices, or `nil` if any element is not a property list that a store accepts.
///
/// A Swift array cannot contain itself, so validating each element validates the array without bridging it.
///
/// See ``storablePropertyList(_:)``.
internal func storableCopies(of objects: [Any]) -> [(index: Int, copy: AnyObject)]? {
    var copies: [(index: Int, copy: AnyObject)] = []
    var index = 0

    // `allSatisfy` reads each element in place, which costs less than iterating indices or enumerated elements.
    let isStorable = objects.allSatisfy { object in
        defer {
            index += 1
        }

        switch storableSnapshot(of: object) {
        case nil:
            return false
        case .unchanged?:
            return true
        case .copied(let copy)?:
            copies.append((index, copy))
            return true
        }
    }

    return isStorable ? copies : nil
}

/// Returns whether `objects` holds the entry at `key` that a dictionary container method wrote and, if `validating`,
/// whether that entry is a property list that a store accepts, replacing a validated entry that holds a mutable
/// container with its snapshot.
///
/// See ``storablePropertyList(_:)``.
internal func isStorableEntry(at key: String, in objects: inout [String: Any], validating: Bool) -> Bool {
    guard let object = objects[key] else {
        return false
    }

    guard validating else {
        return true
    }

    switch storableSnapshot(of: object) {
    case nil:
        return false
    case .unchanged?:
        return true
    case .copied(let copy)?:
        objects[key] = copy
        return true
    }
}

/// Returns whether every entry of `objects`, a dictionary that a dictionary container method defined outside this
/// package wrote, is a property list that a store accepts, replacing each entry that holds a mutable object with its
/// snapshot.
///
/// Such a method receives the entries that earlier calls wrote and can change one after it was validated, such as by
/// adding an archive UID to it, so a write that calls one validates the completed dictionary as well as each entry.
///
/// See ``storablePropertyList(_:)``.
internal func isStorableDictionary(_ objects: inout [String: Any]) -> Bool {
    var holdsMutableObject = false

    // Reading values alone costs much less than reading key-value pairs, and an entry rarely holds a mutable object,
    // so the keys are read only to replace such an entry.
    let isStorable = objects.values.allSatisfy { object in
        switch storableSnapshot(of: object) {
        case nil:
            return false
        case .unchanged?:
            return true
        case .copied?:
            holdsMutableObject = true
            return true
        }
    }

    guard isStorable else {
        return false
    }

    if holdsMutableObject {
        for (key, object) in objects {
            if case .copied(let copy)? = storableSnapshot(of: object) {
                objects[key] = copy
            }
        }
    }

    return true
}

/// Returns the snapshot of `object` if it is a property list that `UserDefaults` and `NSUbiquitousKeyValueStore`
/// accept, or `nil` otherwise.
///
/// Such a property list is a string, number (including a Boolean), date, or data object, or an array or string-keyed
/// dictionary of such objects that does not contain itself. Binary property-list validation also accepts other
/// objects, such as the UIDs in a keyed archive's property list. `UserDefaults` removes the key's previous value before
/// rejecting such an object, so a write must not pass one to a store.
///
/// The snapshot is the Foundation object that `object` bridges to, with every mutable string, data object, array, or
/// dictionary in it replaced by an immutable copy, except dictionary keys, which may be shared. A
/// representation can keep a mutable object it returned and change it while a later value of the same collection is
/// converted, such as by adding an archive UID to a dictionary that has already been validated or by reusing one data
/// buffer for every value, so writes store the snapshot instead.
internal func storablePropertyList(_ object: Any) -> AnyObject? {
    let bridgedObject = object as AnyObject
    var enclosingContainers: [ObjectIdentifier] = []

    switch storableSnapshot(of: bridgedObject, within: &enclosingContainers) {
    case nil:
        return nil
    case .unchanged?:
        return bridgedObject
    case .copied(let copy)?:
        return copy
    }
}

/// Returns how ``storablePropertyList(_:)`` snapshots `object`, or `nil` if it is not a property list that a store
/// accepts.
internal func storableSnapshot(of object: Any) -> StorableSnapshot? {
    guard !isSwiftPropertyListLeaf(object) else {
        return .unchanged
    }

    var enclosingContainers: [ObjectIdentifier] = []

    return storableSnapshot(of: object as AnyObject, within: &enclosingContainers)
}

/// Returns whether `object` is a Swift `String`, `Int`, `Double`, `Bool`, `Data`, or `Date` value.
///
/// Such a value bridges to an immutable string, number, data, or date object, so it is a storable property list and
/// its own snapshot. Comparing its type costs much less than bridging it and comparing Core Foundation type
/// identifiers.
private func isSwiftPropertyListLeaf(_ object: Any) -> Bool {
    let type = type(of: object)

    return type == String.self || type == Int.self || type == Double.self || type == Bool.self || type == Data.self
        || type == Date.self
}

/// How ``storablePropertyList(_:)`` snapshots a property list that a store accepts.
internal enum StorableSnapshot {
    /// The property list holds no mutable object, so it is its own snapshot.
    case unchanged

    /// The property list holds a mutable object, so its snapshot is this copy.
    case copied(AnyObject)
}

/// Returns how `object` is snapshotted, given the containers that enclose it, or `nil` if it is not a storable
/// property list.
///
/// This compares Core Foundation type identifiers, which are what property-list validation compares and cost less than
/// dynamic casts, and reads container elements through Core Foundation without bridging them to Swift values. A
/// string, data object, or container of such a type is a toll-free bridged Foundation object, whose `copy(with:)`
/// returns the object itself if it is immutable, so an object is copied only if it or one of the objects it holds is
/// mutable.
private func storableSnapshot(
    of object: AnyObject,
    within enclosingContainers: inout [ObjectIdentifier]
) -> StorableSnapshot? {
    // Each case calls a Core Foundation function, so the most common types come first.
    switch CFGetTypeID(object) {
    case CFStringGetTypeID():
        return snapshot(ofCopyable: unsafeDowncast(object, to: NSString.self))
    case CFNumberGetTypeID(), CFBooleanGetTypeID(), CFDateGetTypeID():
        return .unchanged
    case CFDataGetTypeID():
        return snapshot(ofCopyable: unsafeDowncast(object, to: NSData.self))
    case CFArrayGetTypeID():
        let array = unsafeDowncast(object, to: CFArray.self)
        let count = CFArrayGetCount(array)

        return withElements(of: object, within: &enclosingContainers) { enclosingContainers in
            withUnsafeTemporaryAllocation(of: UnsafeRawPointer?.self, capacity: count) { elements in
                CFArrayGetValues(array, CFRange(location: 0, length: count), elements.baseAddress)

                guard let copiedElements = storableSnapshots(of: elements, within: &enclosingContainers) else {
                    return nil
                }

                guard let copiedElements else {
                    return snapshot(ofCopyable: unsafeDowncast(object, to: NSArray.self))
                }

                return .copied(NSArray(array: copiedElements))
            }
        }
    case CFDictionaryGetTypeID():
        let dictionary = unsafeDowncast(object, to: CFDictionary.self)
        let count = CFDictionaryGetCount(dictionary)

        return withElements(of: object, within: &enclosingContainers) { enclosingContainers in
            withUnsafeTemporaryAllocation(of: UnsafeRawPointer?.self, capacity: count) { keys in
                withUnsafeTemporaryAllocation(of: UnsafeRawPointer?.self, capacity: count) { values in
                    CFDictionaryGetKeysAndValues(dictionary, keys.baseAddress, values.baseAddress)

                    guard
                        keys.allSatisfy({ CFGetTypeID(storedObject(at: $0)) == CFStringGetTypeID() }),
                        let copiedValues = storableSnapshots(of: values, within: &enclosingContainers)
                    else {
                        return nil
                    }

                    guard let copiedValues else {
                        return snapshot(ofCopyable: unsafeDowncast(object, to: NSDictionary.self))
                    }

                    let copiedKeys = keys.map {
                        unsafeDowncast(storedObject(at: $0), to: NSString.self)
                    }

                    return .copied(NSDictionary(objects: copiedValues, forKeys: copiedKeys))
                }
            }
        }
    default:
        return nil
    }
}

/// Returns the snapshots of `elements`, which a Core Foundation container returned without retaining them, if any of
/// them is a copy; `.some(nil)` if every element is its own snapshot; or `nil` if any element is not a storable
/// property list.
private func storableSnapshots(
    of elements: UnsafeMutableBufferPointer<UnsafeRawPointer?>,
    within enclosingContainers: inout [ObjectIdentifier]
) -> [AnyObject]?? {
    // Most elements are their own snapshots, so the snapshots are collected only once one of them is a copy.
    var snapshots: [AnyObject]?

    for index in elements.indices {
        let element = storedObject(at: elements[index])

        switch storableSnapshot(of: element, within: &enclosingContainers) {
        case nil:
            return nil
        case .unchanged?:
            snapshots?.append(element)
        case .copied(let copy)?:
            if snapshots == nil {
                snapshots = elements[..<index].map(storedObject(at:))
            }

            snapshots?.append(copy)
        }
    }

    return .some(snapshots)
}

/// Returns `.unchanged` if `object`, a string, data object, or container whose elements are their own snapshots, is
/// immutable, or its immutable copy otherwise.
private func snapshot(ofCopyable object: NSCopying & AnyObject) -> StorableSnapshot {
    let copy = object.copy(with: nil) as AnyObject

    return copy === object ? .unchanged : .copied(copy)
}

/// Returns the result of validating the elements of `container` with `body`, or `nil` if `container` encloses itself,
/// which would otherwise recurse forever.
private func withElements(
    of container: AnyObject,
    within enclosingContainers: inout [ObjectIdentifier],
    _ body: (inout [ObjectIdentifier]) -> StorableSnapshot?
) -> StorableSnapshot? {
    let identifier = ObjectIdentifier(container)

    guard !enclosingContainers.contains(identifier) else {
        return nil
    }

    enclosingContainers.append(identifier)

    defer {
        enclosingContainers.removeLast()
    }

    return body(&enclosingContainers)
}

/// Returns the object at `pointer`, an element that a Core Foundation container returned without retaining it.
///
/// Foundation containers cannot hold `nil`, so `pointer` is never `nil`.
private func storedObject(at pointer: UnsafeRawPointer?) -> AnyObject {
    Unmanaged<AnyObject>.fromOpaque(pointer!).takeUnretainedValue()
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

/// Returns an immutable copy of the object that `representation` encodes for `value`, after verifying that the copy
/// decodes.
///
/// The decoder validates the returned copy itself. The copy holds no mutable container or leaf, so a decoder that
/// consumes writable input cannot change the object a caller stores. Throws
/// ``PersistentKeyValueConversionError/encodingFailed`` when the encoded object is not a property list that a store
/// accepts, which ``isStorablePropertyList(_:)`` checks before copying because such an object can contain itself.
internal func encodeStorageRepresentation<Value, Representation: PersistentKeyValueRepresentation>(
    _ representation: Representation,
    value: Value,
    format: PersistentKeyValueStorageFormat
) throws -> Any?
where Representation.Value == Value {
    guard let encoded = try representation.encode(value, format: format) else {
        return nil
    }

    guard isStorablePropertyList(encoded), let object = try? PropertyListMigrationStorage.exactCopy(encoded) else {
        throw PersistentKeyValueConversionError.encodingFailed
    }

    _ = try representation.decode(storageObject: object, format: format)
    return object
}

/// Returns the checked storage object for `value` that migration writes, or `nil` when `value` is an optional that is
/// `nil`, which a Foundation store keeps as an absent key.
///
/// Throws ``PersistentKeyValueConversionError/encodingFailed`` when the key's representation encodes any other value
/// to `nil`, because removing the destination entry would discard a value that migration could not write.
internal func encodeStorageValue<Key: PersistentKeyProtocol>(
    _ value: Key.Value,
    for key: Key,
    format: PersistentKeyValueStorageFormat
) throws -> Any? {
    guard let object = try encodeStorageRepresentation(key.representation, value: value, format: format) else {
        guard isNilOptional(value) else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return nil
    }

    return object
}

/// Whether `value` is an optional that is `nil` at any level of nesting, as `Int??.some(nil)` is.
private func isNilOptional(_ value: Any) -> Bool {
    var value = value
    // The dynamic type check comes first because a cast unwraps an `AnyHashable`, which would make a boxed `nil` look
    // like an optional.
    while type(of: value) is any OptionalElement.Type, let optional = value as? any OptionalElement {
        guard let wrapped = optional.wrappedObject else {
            return true
        }

        value = wrapped
    }

    return false
}
