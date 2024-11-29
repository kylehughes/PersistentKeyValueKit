//
//  CustomPersistibleType.RawRepresentable.swift
//  PersistentKeyValueKitTests
//
//  Created by Kyle Hughes on 4/17/22.
//

import PersistentKeyValueKit

extension CustomPersistibleType {
    public enum RawRepresentable: String, Swift.Codable, Equatable, Sendable {
        case caseOne
        case caseTwo = "CASE_TWO"
    }
}

// MARK: - KeyValuePersistible Extension

extension CustomPersistibleType.RawRepresentable: KeyValuePersistible {
    // MARK: Public Static Interface
    
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}
