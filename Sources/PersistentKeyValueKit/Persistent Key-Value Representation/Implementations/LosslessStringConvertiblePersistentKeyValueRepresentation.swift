//
//  LosslessStringConvertiblePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/15/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore`` for types that can be converted to and from a `String`
/// without losing information.
///
/// This is a proxy representation. The ``Value`` type will be persisted as a `String`, which is itself persistible.
public struct LosslessStringConvertiblePersistentKeyValueRepresentation<Value>
where
    Value: LosslessStringConvertible
{
    // MARK: Public Initialization
    
    /// Creates a new representation.
    @inlinable
    public init() {}
}

// MARK: - ProxyPersistentKeyValueRepresentationProtocol Extension

extension LosslessStringConvertiblePersistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Public Typealiases
    
    public typealias Proxy = String
    
    // MARK: Public Instance Interface
    
    @inlinable
    public func from(_ proxy: Proxy) -> Value? {
        Value(proxy)
    }
    
    @inlinable
    public func to(_ value: Value) -> Proxy? {
        String(value)
    }
}
