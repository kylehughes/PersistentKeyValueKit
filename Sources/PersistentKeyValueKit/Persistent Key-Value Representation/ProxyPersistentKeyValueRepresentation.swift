//
//  ProxyPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// TODO: I had some thought about… do I just need to pass through a representation or something? instead of a
// representation or value? maybe at the generic level? I don't remmemer.

// TODO: ok i did it was it worth it?

public struct ProxyPersistentKeyValueRepresentation<Value, ProxyRepresentation>
where
    ProxyRepresentation: PersistentKeyValueRepresentation
{
    public let deserializing: (ProxyRepresentation.Value) -> Value?
    public let proxyRepresentation: ProxyRepresentation
    public let serializing: (Value) -> ProxyRepresentation.Value
    
    // MARK: Public Initialization
    
    @inlinable
    public init(
        proxyRepresentation: ProxyRepresentation,
        serializing: @escaping (Value) -> ProxyRepresentation.Value,
        deserializing: @escaping (ProxyRepresentation.Value) -> Value?
    ) {
        self.proxyRepresentation = proxyRepresentation
        self.serializing = serializing
        self.deserializing = deserializing
    }
}

// MARK: - ProxyablePersistentKeyValueRepresentation Extension

extension ProxyPersistentKeyValueRepresentation: ProxyablePersistentKeyValueRepresentation {
    // MARK: Public Instnace Interface
    
    @inlinable
    public func deserializing(_ proxy: ProxyRepresentation.Value) -> Value? {
        deserializing(proxy)
    }
    
    @inlinable
    public func serializing(_ value: Value) -> ProxyRepresentation.Value {
        serializing(value)
    }
}

// MARK: - Implementation for Persistible Proxy Representation Values

extension ProxyPersistentKeyValueRepresentation where
    ProxyRepresentation.Value: KeyValuePersistible,
    ProxyRepresentation.Value.PersistentKeyValueRepresentation == ProxyRepresentation
{
    // MARK: Public Initialization
    
    @inlinable
    public init(
        serializing: @escaping (Value) -> ProxyRepresentation.Value,
        deserializing: @escaping (ProxyRepresentation.Value) -> Value?
    ) {
        self.serializing = serializing
        self.deserializing = deserializing
        
        proxyRepresentation = ProxyRepresentation.Value.persistentKeyValueRepresentation
    }
}
