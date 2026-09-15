//
//  CodablePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/15/24.
//

import Combine
import Foundation

/// A representation of a value in a ``PersistentKeyValueStore`` for types that participate in Swift's protocols for 
/// encoding and decoding.
///
/// This is a proxy representation. The ``Value`` type will be persisted as the `Input`/`Output` of the given 
/// ``Encoder`` and ``Decoder``, which must itself be persistible.
///
/// Ordinary store access preserves the existing non-throwing behavior: failure to encode results in no value being
/// stored and failure to decode returns `nil`. The checked representation interface reports the underlying encoder
/// and decoder errors.
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
    
    @inlinable
    public func from(_ proxy: Proxy) -> Value? {
        try? decoder.decode(Value.self, from: proxy)
    }
    
    @inlinable
    public func to(_ value: Value) -> Proxy? {
        try? encoder.encode(value)
    }

    public func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value {
        let proxy = try decodeStorageRepresentation(
            Encoder.Output.persistentKeyValueRepresentation, object: storageObject, format: format)
        return try decoder.decode(Value.self, from: proxy)
    }

    public func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any? {
        let proxy = try encoder.encode(value)
        return try encodeStorageRepresentation(
            Encoder.Output.persistentKeyValueRepresentation, value: proxy, format: format)
    }
}

// MARK: - Extension for Data Coders

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension CodablePersistentKeyValueRepresentation where Encoder == JSONEncoder, Decoder == JSONDecoder {
    // MARK: Public Initialization
    
    /// Creates a new representation with the default `JSONEncoder` and `JSONDecoder`.
    @inlinable
    public init() {
        self.init(encoder: JSONEncoder(), decoder: JSONDecoder())
    }
}
