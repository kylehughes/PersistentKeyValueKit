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
    
    // MARK: Public Initialization
    
    @inlinable
    public init(encoder: Encoder, decoder: Decoder) {
        self.encoder = encoder
        self.decoder = decoder
    }
}

// MARK: - PersistentKeyValueRepresentation Extension

extension CodablePersistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Public Typealiases
    
    public typealias Proxy = Encoder.Output
    
    // MARK: Public Instance Interface
    
    @inlinable
    public func deserializing(_ proxy: Proxy) -> Value? {
        try? decoder.decode(Value.self, from: proxy)
    }
    
    @inlinable
    public func serializing(_ value: Value) -> Proxy? {
        try? encoder.encode(value)
    }
}

// MARK: - Extension for Data Coders

extension CodablePersistentKeyValueRepresentation where Encoder == JSONEncoder, Decoder == JSONDecoder {
    // MARK: Public Initialization
    
    @inlinable
    public init() {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }
}
