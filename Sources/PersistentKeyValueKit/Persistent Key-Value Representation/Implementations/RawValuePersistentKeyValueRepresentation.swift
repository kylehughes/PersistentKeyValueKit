//
//  RawValuePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/15/24.
//

import Foundation

public struct RawValuePersistentKeyValueRepresentation<Value>
where
    Value: RawRepresentable,
    Value.RawValue: KeyValuePersistible
{}

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
