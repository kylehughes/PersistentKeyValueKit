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
    public let from: @Sendable (Proxy) -> Value?

    /// The closure used to serialize a value into its proxy.
    public let to: @Sendable (Value) -> Proxy?
    
    // MARK: Public Initialization
    
    /// Creates a new representation that proxies a value through another explicit representation.
    ///
    /// This is useful for composing representations together. The value of ``Proxy`` is inferred from the
    /// proxied representation, not vice versa.
    ///
    /// - Parameter other: The other representation to proxy through.
    /// - Parameter to: The closure used to serialize a value into the other representation's value.
    /// - Parameter from: The closure used to deserialize a value from the other representation's value.
    public init<Other>(
        other: Other,
        to: @Sendable @escaping (Value) -> Other.Value,
        from: @Sendable @escaping (Other.Value) -> Value
    ) where Other: ProxyPersistentKeyValueRepresentationProtocol, Other.Proxy == Proxy {
        self.to = { @Sendable in
            other.to(to($0))
        }
        
        self.from = { @Sendable in
            guard let otherDeserialization = other.from($0) else {
                return nil
            }
            
            return from(otherDeserialization)
        }
    }
    
    /// Creates a new representation that proxies a value though another persistible type.
    ///
    /// - Parameter to: The closure used to serialize a value into its proxy.
    /// - Parameter from: The closure used to deserialize a value from its proxy.
    @inlinable
    public init(
        to: @Sendable @escaping (Value) -> Proxy,
        from: @Sendable @escaping (Proxy) -> Value
    ) {
        self.to = to
        self.from = from
    }
    
    /// Creates a new representation that proxies a value though another persistible type.
    ///
    /// This specialized initializer is useful for callers using `KeyPath` shorthand with `Optional` values.
    ///
    /// - Parameter to: The closure used to serialize a value into its proxy.
    /// - Parameter from: The closure used to deserialize a value from its proxy.
    @inlinable
    public init(
        to: @Sendable @escaping (Value) -> Proxy?,
        from: @Sendable @escaping (Proxy) -> Value
    ) {
        self.to = to
        self.from = from
    }
    
    /// Creates a new representation that proxies a value though another persistible type.
    ///
    /// This specialized initializer is useful for callers using `KeyPath` shorthand with `Optional` values.
    ///
    /// - Parameter to: The closure used to serialize a value into its proxy.
    /// - Parameter from: The closure used to deserialize a value from its proxy.
    @inlinable
    public init(
        to: @Sendable @escaping (Value) -> Proxy,
        from: @Sendable @escaping (Proxy) -> Value?
    ) {
        self.to = to
        self.from = from
    }
    
    /// Creates a new representation that proxies a value though another persistible type.
    ///
    /// This specialized initializer is useful for callers using `KeyPath` shorthand with `Optional` values.
    ///
    /// - Parameter to: The closure used to serialize a value into its proxy.
    /// - Parameter from: The closure used to deserialize a value from its proxy.
    @inlinable
    public init(
        to: @Sendable @escaping (Value) -> Proxy?,
        from: @Sendable @escaping (Proxy) -> Value?
    ) {
        self.to = to
        self.from = from
    }
}

// MARK: - ProxyPersistentKeyValueRepresentationProtocol Extension

extension ProxyPersistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Public Instance Interface
    
    @inlinable
    public func from(_ proxy: Proxy) -> Value? {
        from(proxy)
    }
    
    @inlinable
    public func to(_ value: Value) -> Proxy? {
        to(value)
    }
}
