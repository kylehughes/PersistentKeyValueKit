import Foundation

/// One unit of a migration batch: a source key, the destination key it migrates to, and an optional value transform.
///
/// The source value is read from the source store and decoded with the source key's
/// ``PersistentKeyProtocol/representation``. A transform, if any, converts it, and the result is encoded with the
/// destination key's representation and written to the destination key. Conflict detection and the conflict policy
/// apply to the destination key in the destination store. An item whose source or destination key has
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
/// Mapping to a different key identifier also lets a migration rename or reshape keys within one store, provided no
/// item maps a key to its own identifier and no item's destination is another item's source.
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
    /// keys can use different storage formats.
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
    /// `transform` runs synchronously during the migration, after the source value is decoded and before anything is
    /// written. If it throws, the item fails at ``PersistentKeyMigrationReport/FailureStage/transform`` with the thrown
    /// error, and neither store is modified for this item, including the source during a move. `transform` does not
    /// run when the source value is absent, when either key is disabled, or when the conflict policy keeps the existing
    /// destination value. It can run again if the migration is retried.
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
        Self(mapping: PersistentKeyMigrationMapping(source: source, destination: destination, transform: transform))
    }
}
