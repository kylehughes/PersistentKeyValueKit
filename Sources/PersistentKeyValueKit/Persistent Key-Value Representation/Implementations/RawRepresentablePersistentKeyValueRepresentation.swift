//
//  RawRepresentablePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/15/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore`` for `RawRepresentable` types whose `RawValue` conforms
/// to ``KeyValuePersistible``.
///
/// This is a proxy representation that persists `Value` as its `RawValue`.
public struct RawRepresentablePersistentKeyValueRepresentation<Value>
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

extension RawRepresentablePersistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Public Typealiases
    
    public typealias Proxy = Value.RawValue
    
    // MARK: Public Instance Interface
    
    @inlinable
    public func from(_ proxy: Proxy) -> Value? {
        Value(rawValue: proxy)
    }
    
    @inlinable
    public func to(_ value: Value) -> Proxy? {
        value.rawValue
    }
}

// MARK: - BuiltInProxyConversion Extension

extension RawRepresentablePersistentKeyValueRepresentation: BuiltInProxyConversion {}
