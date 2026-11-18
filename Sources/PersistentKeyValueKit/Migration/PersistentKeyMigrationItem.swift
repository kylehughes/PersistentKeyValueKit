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
/// Mapping to a different key identifier also lets a migration rename or reshape keys within one store, provided no
/// item's destination is another item's source. Within one store, an item can map a key to its own identifier only
/// when it was created with ``key(_:to:transform:)``; it then rewrites the value in place, as described there.
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
            mapping: PersistentKeyMigrationMapping(source: key, destination: key, hasTransform: false) {
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
            mapping: PersistentKeyMigrationMapping(source: source, destination: destination, hasTransform: false) {
                $0
            }
        )
    }

    /// Migrates `source` to `destination`, converting each value with `transform`.
    ///
    /// `transform` runs synchronously during the migration, after the source value is decoded and before anything is
    /// written. If its initial call throws, the item fails at ``PersistentKeyMigrationReport/FailureStage/transform``
    /// with the thrown error, and neither store is modified for this item, including the source during a move.
    /// `transform` does not run when the source value is absent, when either key is disabled, or when the conflict
    /// policy keeps the existing destination value. It can run again if the migration is retried, and an in-place
    /// rewrite can run it again on its own result, as described below.
    ///
    /// When the migration's source and destination are the same store and `source` and `destination` have the same
    /// identifier, the item rewrites the stored value in place: it decodes the value with `source`'s representation,
    /// converts it with `transform`, encodes the result with `destination`'s representation, and replaces the stored
    /// value only if it has not changed since it was read. The existing value is the one being rewritten, so it is not
    /// a destination conflict, and every conflict policy rewrites it. A move does not remove the key as a source, and
    /// the item reports ``PersistentKeyMigrationReport/Status/rewritten``. As with any write, the key is removed only
    /// when `destination`'s representation stores no object for the result, such as `nil` for an optional key in a
    /// Foundation store. Pass `{ $0 }` as `transform` to change only the representation. Items created with
    /// ``key(_:)`` or ``key(_:to:)`` never rewrite in place; mapping a key to its own identifier within one store with
    /// them throws ``PersistentKeyMigrationError/sameStore``, as does a rewrite between two different instances for one
    /// store.
    ///
    /// A tracked migration runs its whole batch again after any item fails, so an in-place rewrite can find a value it
    /// already rewrote. A stored value that fails to decode with `source`'s representation but decodes with
    /// `destination`'s is treated as already rewritten: after verifying that the stored snapshot has not changed while
    /// decoding (failing at ``PersistentKeyMigrationReport/FailureStage/write`` with
    /// ``PersistentKeyMigrationError/destinationChanged`` if it changed), the item reports
    /// ``PersistentKeyMigrationReport/Status/rewritten`` without running `transform` or writing. A rewritten value that
    /// still decodes with `source`'s representation would be rewritten again, so before writing, the item decodes its
    /// result that way and runs `transform` on it again. Unless that succeeds without changing the first prepared
    /// result and produces the same stored value (requiring reproducible encoding, such as `JSONEncoder` with
    /// `.sortedKeys`, when `source` can decode the encoded result), the item fails at
    /// ``PersistentKeyMigrationReport/FailureStage/prepare`` with ``PersistentKeyMigrationError/nonIdempotentRewrite``
    /// and nothing is written.
    ///
    /// A rewrite is therefore safe to retry only when every value `destination`'s representation stores fails to
    /// decode with `source`'s representation, such as an integer rewritten as a string, or when `transform` and
    /// `destination`'s encoding are idempotent on their own results. Storage formats overlap more than their Swift
    /// types suggest: Foundation stores bridge numbers, so a `Bool`, an `Int`, and an integral `Double` can decode as
    /// one another, and an ``InMemoryPersistentKeyValueStore`` skips representations, so it decodes any value of the
    /// source key's type (and rejects same-type rewrites of non-`Equatable` values, reference results other than
    /// Foundation property-list objects, or results that verification mutates in place). To change a value in an
    /// overlapping format, such as converting dollars to cents or seconds to milliseconds, migrate it to a new key
    /// with ``key(_:to:transform:)`` instead, so a repeated run finds no source value.
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
            mapping: PersistentKeyMigrationMapping(
                source: source,
                destination: destination,
                hasTransform: true,
                transform: transform
            )
        )
    }
}
