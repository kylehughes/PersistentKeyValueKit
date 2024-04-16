//
//  RawValuePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/15/24.
//

import Foundation

@inlinable
public func RawValuePersistentKeyValueRepresentation<Value>(
) -> ProxyPersistentKeyValueRepresentation<Value, Value.RawValue> where Value: RawRepresentable {
    ProxyPersistentKeyValueRepresentation(
        serializing: \.rawValue,
        deserializing: Value.init(rawValue:)
    )
}

// MARK: - Extension for Proxy Representation for RawRepresentable Values

extension ProxyPersistentKeyValueRepresentation
where
    Value: RawRepresentable,
    Value.RawValue: KeyValuePersistible,
    Proxy == Value.RawValue
{
    // MARK: Public Static Interface
    
    @inlinable
    public static var rawValue: ProxyPersistentKeyValueRepresentation<Value, Value.RawValue> {
        RawValuePersistentKeyValueRepresentation()
    }
}
