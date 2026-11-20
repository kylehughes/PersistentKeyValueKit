//
//  CodablePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/15/24.
//

import Combine
import Foundation

/// A representation of a value in a ``PersistentKeyValueStore`` for types that conform to `Encodable` and `Decodable`.
///
/// This is a proxy representation. `Value` is persisted as the `Input`/`Output` type of the supplied `Encoder` and
/// `Decoder`, which must itself conform to ``KeyValuePersistible``.
///
/// Ordinary store reads and writes remain non-throwing: encoding failures leave the store unchanged and decoding
/// failures fall back to the key's default value. Checked conversion via ``decode(storageObject:format:)`` and
/// ``encode(_:format:)`` rethrows the underlying `Encoder` and `Decoder` errors.
public struct CodablePersistentKeyValueRepresentation<Value, Encoder, Decoder>
where
    Value: Decodable & Encodable,
    Encoder: TopLevelEncoder & Sendable,
    Decoder: TopLevelDecoder & Sendable,
    Encoder.Output: KeyValuePersistible,
    Encoder.Output == Decoder.Input
{
    /// The decoder used to deserialize values from a ``PersistentKeyValueStore``.
    public let decoder: Decoder

    /// The encoder used to serialize values for a ``PersistentKeyValueStore``.
    public let encoder: Encoder
    
    // MARK: Public Initialization
    
    /// Creates a new representation with the given encoder and decoder.
    ///
    /// - Parameter encoder: The encoder used to serialize values for a ``PersistentKeyValueStore``.
    /// - Parameter decoder: The decoder used to deserialize values from a ``PersistentKeyValueStore``.
    @inlinable
    public init(encoder: Encoder, decoder: Decoder) {
        self.encoder = encoder
        self.decoder = decoder
    }
}

// MARK: - PersistentKeyValueRepresentation Extension

extension CodablePersistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Public Typealiases
    
    public typealias Proxy = Encoder.Output
    
    // MARK: Public Instance Interface

    /// Decodes a stored object into `Proxy` and decodes `Value` with ``decoder``, rethrowing any `Decoder` error.
    public func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value {
        let proxy = try Encoder.Output.persistentKeyValueRepresentation.decode(
            storageObject: storageObject,
            format: format
        )
        return try decoder.decode(Value.self, from: proxy)
    }

    /// Encodes `value` into `Proxy` with ``encoder`` and encodes the result for `format`, rethrowing any `Encoder`
    /// error.
    ///
    /// If the proxy's representation encodes no object, this method returns `nil`. Otherwise it verifies that the proxy
    /// can decode the immutable copy and returns that copy. Throws
    /// ``PersistentKeyValueConversionError/encodingFailed`` when `Proxy`'s encoding is not a property list.
    public func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any? {
        let proxy = try encoder.encode(value)
        return try encodeStorageRepresentation(
            Encoder.Output.persistentKeyValueRepresentation,
            value: proxy,
            format: format
        )
    }

    @inlinable
    public func from(_ proxy: Proxy) -> Value? {
        try? decoder.decode(Value.self, from: proxy)
    }

    @inlinable
    public func to(_ value: Value) -> Proxy? {
        try? encoder.encode(value)
    }
}

// MARK: - BuiltInProxyConversion Extension

extension CodablePersistentKeyValueRepresentation: BuiltInProxyConversion {
    // MARK: Internal Instance Interface

    func checkedProxy(for value: Value) throws -> Proxy {
        try encoder.encode(value)
    }

    func checkedValue(for proxy: Proxy) throws -> Value {
        try decoder.decode(Value.self, from: proxy)
    }
}

// MARK: - Extension for Data Coders

extension CodablePersistentKeyValueRepresentation where Encoder == JSONEncoder, Decoder == JSONDecoder {
    // MARK: Public Initialization
    
    /// Creates a new representation with the default `JSONEncoder` and `JSONDecoder`.
    @inlinable
    public init() {
        self.init(encoder: JSONEncoder(), decoder: JSONDecoder())
    }
}
