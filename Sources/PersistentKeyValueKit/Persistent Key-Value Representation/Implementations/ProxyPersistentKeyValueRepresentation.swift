//
//  ProxyPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/20/24.
//

/// A representation of a value in a ``PersistentKeyValueStore`` that is proxied through another persistible type.
///
/// This is a concrete implementation of ``ProxyPersistentKeyValueRepresentationProtocol``.
public struct ProxyPersistentKeyValueRepresentation<Value, Proxy> where Proxy: KeyValuePersistible {
    /// The closure used to deserialize a value from its proxy.
    public let deserializing: (Proxy) -> Value?

    /// The closure used to serialize a value into its proxy.
    public let serializing: (Value) -> Proxy?
    
    // MARK: Public Initialization
    
    /// Creates a new representation that proxies a value through another explicit representation.
    ///
    /// This is useful for composing representations together. The value of ``Proxy`` is inferred from the
    /// proxied representation, not vice versa.
    ///
    /// - Parameter other: The other representation to proxy through.
    /// - Parameter serializing: The closure used to serialize a value into the other representation's value.
    /// - Parameter deserializing: The closure used to deserialize a value from the other representation's value.
    @inlinable
    public init<Other>(
        other: Other,
        serializing: @escaping (Value) -> Other.Value,
        deserializing: @escaping (Other.Value) -> Value
    ) where Other: ProxyPersistentKeyValueRepresentationProtocol, Other.Proxy == Proxy {
        self.serializing = {
            other.serializing(serializing($0))
        }
        
        self.deserializing = {
            guard let otherDeserialization = other.deserializing($0) else {
                return nil
            }
            
            return deserializing(otherDeserialization)
        }
    }
    
    /// Creates a new representation that proxies a value though another persistible type.
    ///
    /// - Parameter serializing: The closure used to serialize a value into its proxy.
    /// - Parameter deserializing: The closure used to deserialize a value from its proxy.
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy, deserializing: @escaping (Proxy) -> Value) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
    
    /// Creates a new representation that proxies a value though another persistible type.
    ///
    /// This specialized initializer is useful for callers using `KeyPath` shorthand with `Optional` values.
    ///
    /// - Parameter serializing: The closure used to serialize a value into its proxy.
    /// - Parameter deserializing: The closure used to deserialize a value from its proxy.
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy?, deserializing: @escaping (Proxy) -> Value) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
    
    /// Creates a new representation that proxies a value though another persistible type.
    ///
    /// This specialized initializer is useful for callers using `KeyPath` shorthand with `Optional` values.
    ///
    /// - Parameter serializing: The closure used to serialize a value into its proxy.
    /// - Parameter deserializing: The closure used to deserialize a value from its proxy.
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy, deserializing: @escaping (Proxy) -> Value?) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
    
    /// Creates a new representation that proxies a value though another persistible type.
    ///
    /// This specialized initializer is useful for callers using `KeyPath` shorthand with `Optional` values.
    ///
    /// - Parameter serializing: The closure used to serialize a value into its proxy.
    /// - Parameter deserializing: The closure used to deserialize a value from its proxy.
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy?, deserializing: @escaping (Proxy) -> Value?) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
}

// MARK: - ProxyPersistentKeyValueRepresentationProtocol Extension

extension ProxyPersistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Public Instnace Interface
    
    @inlinable
    public func deserializing(_ proxy: Proxy) -> Value? {
        deserializing(proxy)
    }
    
    @inlinable
    public func serializing(_ value: Value) -> Proxy? {
        serializing(value)
    }
}
