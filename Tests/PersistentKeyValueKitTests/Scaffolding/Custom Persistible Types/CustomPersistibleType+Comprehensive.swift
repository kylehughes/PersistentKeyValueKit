//
//  CustomPersistibleType+Comprehensive.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/12/24.
//

import Foundation
import PersistentKeyValueKit

extension CustomPersistibleType {
    /// A type that contains one of every persistible type.
    ///
    /// We purposefully do not conform this to ``KeyValuePersistible`` so as to encourage testing it with multiple
    /// proxy representations (i.e. ``StringlyKeyedDictionaryPersistentKeyValueRepresentation`` and
    /// ``CodablePersistentKeyValueRepresentation``). It also serves to gurantee that complex types that do not conform
    /// can still be persisted with a representation that is passed to a ``PersistentKeyProtocol`` implementation.
    ///
    /// This is a (minor) superset of ``CustomPersistibleType.StringlyKeyedDictionary``.
    public struct Comprehensive: Swift.Codable, Sendable {
        public let arrayOfPrimitives: [Int]
        public let arrayOfProxies: [CustomPersistibleType.Proxy]
        public let bool: Bool
        public let codable: CustomPersistibleType.Codable
        public let data: Data
        public let double: Double
        public let float: Float
        public let int: Int
        public let losslessStringConvertible: CustomPersistibleType.LosslessStringConvertible
        public let proxy: CustomPersistibleType.Proxy
        public let rawRepresentable: CustomPersistibleType.RawRepresentable
        public let string: String
        public let stringOptional: String?
        public let url: URL
    }
}

// MARK: - Constants

extension CustomPersistibleType.Comprehensive {
    public static let large = Self(
        arrayOfPrimitives: [1, 2, 3, 4, 5],
        arrayOfProxies: [.distantPast, .distantFuture],
        bool: true,
        codable: .large,
        data: Data([0xDE, 0xAD, 0xBE, 0xEF]),
        double: .greatestFiniteMagnitude,
        float: .greatestFiniteMagnitude,
        int: .max,
        losslessStringConvertible: "🙂",
        proxy: .distantFuture,
        rawRepresentable: .caseOne,
        string: String(Array(repeating: "A", count: 1_000)),
        stringOptional: nil,
        url: URL(string: "https://kylehugh.es")!
    )
    
    public static let small = Self(
        arrayOfPrimitives: [],
        arrayOfProxies: [],
        bool: false,
        codable: .small,
        data: Data([0x12, 0x34, 0x56, 0x78]),
        double: .leastNormalMagnitude,
        float: .leastNormalMagnitude,
        int: .min,
        losslessStringConvertible: "☹️",
        proxy: .distantPast,
        rawRepresentable: .caseTwo,
        string: "",
        stringOptional: nil,
        url: URL(string: "https://kylehugh.es")!
    )
}

// MARK: - Representations

extension CustomPersistibleType.Comprehensive {
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    public static let codableRepresentation = CodablePersistentKeyValueRepresentation<
        CustomPersistibleType.Comprehensive,
        JSONEncoder,
        JSONDecoder
    >()
}
