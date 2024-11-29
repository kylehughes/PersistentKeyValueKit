//
//  CustomPersistibleType+LosslessStringConvertible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/30/24.
//

import Foundation
import PersistentKeyValueKit

extension CustomPersistibleType {
    public typealias LosslessStringConvertible = Character
}

// MARK: - Decodable Extension

extension Character: @retroactive Decodable {
    // MARK: Public Initialization
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        
        guard let character = string.first, string.count == 1 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid character: \(string). Expected single character string."
            )
        }
        
        self = character
    }
}

// MARK: - Encodable Extension

extension Character: @retroactive Encodable {
    // MARK: Public Instance Interface
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        try container.encode(String(self))
    }
}

// MARK: - KeyValuePersistible Extension

extension CustomPersistibleType.LosslessStringConvertible: KeyValuePersistible {
    // MARK: Public Static Interface
    
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        LosslessStringConvertiblePersistentKeyValueRepresentation()
    }
}
