//
//  CodablePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/15/24.
//

import Combine
import Foundation

public struct CodablePersistentKeyValueRepresentation<Value, Encoder, Decoder>
where
    Value: Decodable & Encodable & KeyValuePersistible,
    Encoder: TopLevelEncoder,
    Decoder: TopLevelDecoder,
    Encoder.Output: KeyValuePersistible,
    Encoder.Output == Decoder.Input
{
    public let decoder: Decoder
    public let encoder: Encoder
    public let representation: Encoder.Output.PersistentKeyValueRepresentation
    
    // MARK: Public Initialization
    
    @inlinable
    public init(encoder: Encoder, decoder: Decoder) {
        self.encoder = encoder
        self.decoder = decoder
        
        representation = Encoder.Output.persistentKeyValueRepresentation
    }
}

// MARK: - PersistentKeyValueRepresentation Extension

extension CodablePersistentKeyValueRepresentation: PersistentKeyValueRepresentation {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        guard let encodedValue = representation.get(userDefaultsKey, from: userDefaults) else {
            return nil
        }
        
        return try? decoder.decode(Value.self, from: encodedValue)
    }
    
    @inlinable
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        guard let encodedValue = try? encoder.encode(value) else {
            return
        }
        
        representation.set(userDefaultsKey, to: encodedValue, in: userDefaults)
    }
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        guard let encodedValue = representation.get(ubiquitousStoreKey, from: ubiquitousStore) else {
            return nil
        }
        
        return try? decoder.decode(Value.self, from: encodedValue)
    }
    
    @inlinable
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        guard let encodedValue = try? encoder.encode(value) else {
            return
        }
        
        representation.set(ubiquitousStoreKey, to: encodedValue, in: ubiquitousStore)
    }
}

// MARK: - Extension for Data Coders

extension CodablePersistentKeyValueRepresentation where Encoder == JSONEncoder, Decoder == JSONDecoder {
    // MARK: Public Initialization
    
    @inlinable
    public init() {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        representation = Encoder.Output.persistentKeyValueRepresentation
    }
}
