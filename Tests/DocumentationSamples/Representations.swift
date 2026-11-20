// README samples: making types persistible.

import Foundation
import PersistentKeyValueKit

// MARK: - Samples

extension Date: @retroactive KeyValuePersistible {
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        ProxyPersistentKeyValueRepresentation(
            to: \.timeIntervalSinceReferenceDate,
            from: { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }
}

nonisolated enum NotificationFrequency: String {
    case daily
    case weekly
    case monthly
}

extension NotificationFrequency: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}

nonisolated struct Contact: Codable, Sendable {
    let nickname: String
    let dateOfBirth: Date
}

extension Contact: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        CodablePersistentKeyValueRepresentation()
    }
}

extension Character: @retroactive KeyValuePersistible {
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        LosslessStringConvertiblePersistentKeyValueRepresentation()
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<Date?> {
    static var mostRecentAppStoreReviewRequestDate: Self {
        Self(
            "MostRecentAppStoreReviewRequestDate",
            defaultValue: nil,
            representation: ProxyPersistentKeyValueRepresentation(
                to: { (date: Date) in date.ISO8601Format() },
                from: { string in try? Date.ISO8601FormatStyle().parse(string) }
            )
        )
    }
}
