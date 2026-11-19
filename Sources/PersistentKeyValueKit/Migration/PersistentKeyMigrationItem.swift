import Foundation

/// One unit of a migration batch: a source key, the destination key it migrates to, and an optional value transform.
///
/// The source value is read from the source store and decoded with the source key's
/// ``PersistentKeyProtocol/representation``. A transform, if any, converts it, and the result is encoded with the
/// destination key's representation and written to the destination key. ``InMemoryPersistentKeyValueStore`` keeps
/// Swift values rather than encoded objects, so it skips the representation on its side of a migration; a migration
/// between two in-memory stores transfers the Swift value without decoding or encoding it. Conflict detection and the
/// conflict policy apply to the destination key in the destination store. An item whose source or destination key has
/// ``PersistentKeyProtocol/isMigrationEnabled`` set to `false` reports
/// ``PersistentKeyMigrationReport/Status/keyDisabled``.
///
/// A batch can mix items of different value types:
///
/// ```swift
/// let report = try UserDefaults.standard.move(
///     items: [
///         .key(.theme),
///         .key(.oldLaunchCount, to: .launchCount),
///         .key(.legacyFlag, to: .mode, transform: { $0 ? .on : .off }),
///     ],
///     to: appGroup,
///     onConflict: .keepBoth,
///     tracking: .once(id: "app-group-v1")
/// )
/// ```
///
/// A source and a destination are the same key when the store treats their identifiers as one key. `UserDefaults` and
/// `NSUbiquitousKeyValueStore` compare literal UTF-16 code units, so a composed-to-decomposed rename of the same text
/// is a different key there, while ``InMemoryPersistentKeyValueStore`` uses Swift string equality and treats it as the
/// same key.
///
/// Mapping to a different key identifier also lets a migration rename or reshape keys within one store, provided no
/// item's destination is another item's source. An item that maps a key to its own identifier within one store throws
/// ``PersistentKeyMigrationError/sameStore``.
public struct PersistentKeyMigrationItem: Sendable {
    let mapping: any PersistentKeyMigrationMappingProtocol

    // MARK: Private Initialization

    private init(mapping: any PersistentKeyMigrationMappingProtocol) {
        self.mapping = mapping
    }

    // MARK: Public Static Interface

    /// Migrates `key` to the same key in the destination store.
    ///
    /// - Parameter key: The key to migrate.
    /// - Returns: An item whose source and destination keys are both `key`.
    public static func key<Key>(_ key: Key) -> Self where Key: PersistentKeyProtocol {
        Self(
            mapping: PersistentKeyMigrationMapping(source: key, destination: key) {
                $0
            }
        )
    }

    /// Migrates `source` to `destination`, a key with the same value type.
    ///
    /// The value is decoded with `source`'s representation and encoded with `destination`'s representation, so the two
    /// keys can use different storage formats. An ``InMemoryPersistentKeyValueStore`` source or destination keeps the
    /// Swift value and skips the corresponding representation.
    ///
    /// - Parameter source: The key to read from the source store.
    /// - Parameter destination: The key to write in the destination store.
    /// - Returns: An item that migrates `source` to `destination`.
    public static func key<Source, Destination>(_ source: Source, to destination: Destination) -> Self
    where Source: PersistentKeyProtocol, Destination: PersistentKeyProtocol, Source.Value == Destination.Value {
        Self(
            mapping: PersistentKeyMigrationMapping(source: source, destination: destination) {
                $0
            }
        )
    }

    /// Migrates `source` to `destination`, converting each value with `transform`.
    ///
    /// `transform` runs synchronously during the migration, in input order, after the source value is decoded and
    /// before anything is written. A later failure at ``PersistentKeyMigrationReport/FailureStage/prepare`` or
    /// ``PersistentKeyMigrationReport/FailureStage/write`` can still prevent the write. If it throws, the item fails at ``PersistentKeyMigrationReport/FailureStage/transform`` with the
    /// thrown error, and the migration writes to neither store for this item, so a move keeps the source. An
    /// ``InMemoryPersistentKeyValueStore`` source passes `transform` the stored value itself rather than a decoded
    /// copy, so mutating a reference that `transform` receives, such as an `NSMutableArray`, changes the stored source
    /// even if `transform` then throws. Copy a mutable input before changing it. `transform` does not run when the
    /// source value is absent, when either key is disabled, or when the conflict policy keeps the existing destination
    /// value.
    ///
    /// Within one store, `source` and `destination` must have different identifiers, as for any item; mapping a key
    /// to itself throws ``PersistentKeyMigrationError/sameStore``. To change a key's stored representation or convert
    /// its value, such as dollars to cents, move it to a new key, so a retry never reads its own result.
    ///
    /// `transform` can run again if the migration is retried. Whether it does depends on whether the source value
    /// remains and whether the retry writes. A move that removed its source finds no source value. When the source
    /// value remains, a policy that keeps an existing destination value, such as
    /// ``PersistentKeyCopyConflictPolicy/keepDestination`` or ``PersistentKeyMoveConflictPolicy/keepBoth``, keeps it
    /// without running `transform`, including a value that an earlier attempt wrote, and
    /// ``PersistentKeyMoveConflictPolicy/keepBoth`` leaves the source value in place too. Under
    /// ``PersistentKeyCopyConflictPolicy/overwriteDestination`` or
    /// ``PersistentKeyMoveConflictPolicy/overwriteDestination``, the retry converts the source value again and replaces
    /// the earlier result.
    ///
    /// - Parameter source: The key to read from the source store.
    /// - Parameter destination: The key to write in the destination store.
    /// - Parameter transform: Converts a decoded source value to the destination value.
    /// - Returns: An item that migrates `source` to `destination` through `transform`.
    public static func key<Source, Destination>(
        _ source: Source,
        to destination: Destination,
        transform: @escaping @Sendable (Source.Value) throws -> Destination.Value
    ) -> Self
    where Source: PersistentKeyProtocol, Destination: PersistentKeyProtocol {
        Self(
            mapping: PersistentKeyMigrationMapping(source: source, destination: destination, transform: transform)
        )
    }
}
