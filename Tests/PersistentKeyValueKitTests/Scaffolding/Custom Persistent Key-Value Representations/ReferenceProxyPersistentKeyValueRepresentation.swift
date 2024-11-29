//
//  ReferenceProxyPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/1/24.
//

import PersistentKeyValueKit

public final class ReferenceProxyPersistentKeyValueRepresentation<Value, Proxy: KeyValuePersistible> {
    private let deserializing: @Sendable (Proxy) -> Value?
    private let serializing: @Sendable (Value) -> Proxy?
    
    // MARK: Public Initialization
    
    public init(
        serializing: @Sendable @escaping (Value) -> Proxy?,
        deserializing: @Sendable @escaping (Proxy) -> Value?
    ) {
        self.serializing = serializing
        self.deserializing = deserializing
    }
}

// MARK: - ProxyPersistentKeyValueRepresentationProtocol Extension

extension ReferenceProxyPersistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Public Instance Interface
    
    public func from(_ proxy: Proxy) -> Value? {
        deserializing(proxy)
    }
    
    public func to(_ value: Value) -> Proxy? {
        serializing(value)
    }
}
