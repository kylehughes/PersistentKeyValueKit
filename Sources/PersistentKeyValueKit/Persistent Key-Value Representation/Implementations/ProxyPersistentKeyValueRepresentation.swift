//
//  ProxyPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/20/24.
//

public struct ProxyPersistentKeyValueRepresentation<Value, Proxy> where Proxy: KeyValuePersistible {
    public let deserializing: (Proxy) -> Value?
    public let serializing: (Value) -> Proxy?
    
    // MARK: Public Initialization
    
    @inlinable
    public init<Other>(
        other: Other,
        serializing: @escaping (Value) -> Other.Value,
        deserializing: @escaping (Other.Value) -> Value
    ) where Other: ProxyablePersistentKeyValueRepresentation, Other.Proxy == Proxy {
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
    
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy, deserializing: @escaping (Proxy) -> Value) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
    
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy?, deserializing: @escaping (Proxy) -> Value) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
    
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy, deserializing: @escaping (Proxy) -> Value?) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
    
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy?, deserializing: @escaping (Proxy) -> Value?) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
}

// MARK: - ProxyablePersistentKeyValueRepresentation Extension

extension ProxyPersistentKeyValueRepresentation: ProxyablePersistentKeyValueRepresentation {
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
