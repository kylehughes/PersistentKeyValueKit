//
//  FoundationMigrationBackend.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/19/26.
//

import Foundation

// MARK: - FoundationMigrationBackend Definition

/// A migration backend for a Foundation store, which keeps property-list objects under literal key identifiers.
protocol FoundationMigrationBackend: PersistentKeyValueMigrationBackend
where MigrationSnapshot == FoundationMigrationSnapshot, MigrationWrite == FoundationMigrationWrite {
}

extension FoundationMigrationBackend {
    // MARK: Internal Instance Interface

    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity {
        .literal(keyID)
    }

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        guard snapshot.identity == migrationIdentity, LiteralKeyID.match(snapshot.keyID, keyID) else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        let current = try migrationSnapshot(for: keyID)
        return PropertyListStorage.equal(snapshot.object, current?.object)
    }
}

// MARK: - FoundationMigrationSnapshot Definition

struct FoundationMigrationSnapshot {
    let identity: PersistentKeyValueMigrationStoreIdentity
    let keyID: String
    let object: Any
}

// MARK: - FoundationMigrationWrite Definition

struct FoundationMigrationWrite {
    let identity: PersistentKeyValueMigrationStoreIdentity
    let keyID: String
    let object: Any?
}

// MARK: - Storage Value Coding

/// Decodes `object`, read from a Foundation store, with the key's representation.
internal func decodeStorageValue<Key: PersistentKeyProtocol>(
    for key: Key,
    object: Any,
    format: PersistentKeyValueStorageFormat
) throws -> Key.Value {
    try key.representation.decode(storageObject: object, format: format)
}

/// Returns the checked storage object for `value` that migration writes, or `nil` when `value` is an optional that is
/// `nil`, which a Foundation store keeps as an absent key.
///
/// Throws ``PersistentKeyValueConversionError/encodingFailed`` when the key's representation encodes any other value
/// to `nil`, because removing the destination entry would discard a value that migration could not write.
internal func encodeStorageValue<Key: PersistentKeyProtocol>(
    _ value: Key.Value,
    for key: Key,
    format: PersistentKeyValueStorageFormat
) throws -> Any? {
    guard let object = try encodeStorageRepresentation(key.representation, value: value, format: format) else {
        guard isNilOptional(value) else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return nil
    }

    return object
}

/// Whether `value` is an optional that is `nil` at any level of nesting, as `Int??.some(nil)` is.
private func isNilOptional(_ value: Any) -> Bool {
    var value = value
    // The dynamic type check comes first because a cast unwraps an `AnyHashable`, which would make a boxed `nil` look
    // like an optional.
    while type(of: value) is any OptionalElement.Type, let optional = value as? any OptionalElement {
        guard let wrapped = optional.wrappedObject else {
            return true
        }

        value = wrapped
    }

    return false
}
