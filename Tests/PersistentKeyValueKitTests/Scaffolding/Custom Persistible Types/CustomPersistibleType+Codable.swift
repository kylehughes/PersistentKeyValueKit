//
//  CustomPersistibleType+Codable.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/17/22.
//

import Foundation
import PersistentKeyValueKit

extension CustomPersistibleType {
    public struct Codable: Swift.Codable, Equatable, Sendable {
        public let int: Int
        public let string: String
        
        // MARK: Public Initialization
        
        @inlinable
        public init(int: Int, string: String) {
            self.int = int
            self.string = string
        }
    }
}

// MARK: - KeyValuePersistible Extension

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension CustomPersistibleType.Codable: KeyValuePersistible {
    // MARK: Public Static Interface
    
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        CodablePersistentKeyValueRepresentation(encoder: encoder, decoder: decoder)
    }
}

// MARK: - Constants

extension CustomPersistibleType.Codable {
    public static let large = Self(int: .max, string: String(Array(repeating: "A", count: 1_000)))
    public static let small = Self(int: .min, string: "")
}

// MARK: - Coders

extension CustomPersistibleType.Codable {
    public static let decoder = JSONDecoder()
    
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}
