//
//  RawValuePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/15/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore`` for types that can be associated as raw values.
///
/// This is a proxy representation. The ``Value`` type will be persisted as its `RawValue`, which must itself be
/// persistible.
public struct RawValuePersistentKeyValueRepresentation<Value>
where
    Value: RawRepresentable,
    Value.RawValue: KeyValuePersistible
{
    // MARK: Public Initialization

    /// Creates a new representation.
    @inlinable
    public init() {}
}

// MARK: - ProxyPersistentKeyValueRepresentationProtocol Extension

extension RawValuePersistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Public Typealiases
    
    public typealias Proxy = Value.RawValue
    
    // MARK: Public Instance Interface
    
    @inlinable
    public func deserializing(_ proxy: Proxy) -> Value? {
        Value(rawValue: proxy)
    }
    
    @inlinable
    public func serializing(_ value: Value) -> Proxy? {
        value.rawValue
    }
}
