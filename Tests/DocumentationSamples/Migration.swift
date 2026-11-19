// README and release notes samples: migrating values between stores.

import Foundation
import PersistentKeyValueKit

// MARK: - Stubs

enum RuntimeColorScheme: String, KeyValuePersistible {
    case dark
    case light
    case system

    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<RuntimeColorScheme> {
    static var runtimeColorScheme: Self {
        Self("RuntimeColorScheme", defaultValue: .system)
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 0)
    }

    static var legacyLaunchCount: Self {
        Self("LegacyLaunchCount", defaultValue: 0)
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<Bool> {
    static var legacyDarkModeEnabled: Self {
        Self("LegacyDarkModeEnabled", defaultValue: false)
    }
}

func handleMigrationError(_ error: any Error, at status: PersistentKeyMigrationReport.Status) {
}

// MARK: - Samples

func makeAppGroupDefaults() throws -> UserDefaults? {
    guard let appGroup = UserDefaults.migratable(suiteName: "group.example.app") else {
        return nil
    }

    let report = try UserDefaults.standard.move(
        [.runtimeColorScheme, .launchCount],
        to: appGroup,
        onConflict: .keepBoth,
        tracking: .once(id: "app-group-preferences-v1")
    )
    try report.throwIfIncomplete()

    return appGroup
}

func moveItemsToAppGroup(appGroup: UserDefaults) throws {
    let report = try UserDefaults.standard.move(
        items: [
            .key(.legacyLaunchCount, to: .launchCount),
            .key(
                .legacyDarkModeEnabled,
                to: .runtimeColorScheme,
                transform: { isDarkModeEnabled in
                    isDarkModeEnabled ? .dark : .light
                }
            ),
        ],
        to: appGroup,
        onConflict: .keepBoth,
        tracking: .once(id: "app-group-preferences-v2")
    )
    try report.throwIfIncomplete()
}

func seedUbiquitousStore() throws {
    let report = try UserDefaults.standard.copy(
        [.runtimeColorScheme, .launchCount],
        to: .ubiquitous,
        onConflict: .keepDestination,
        tracking: .once(id: "icloud-initial-seed-v1", recordedIn: UserDefaults.standard)
    )

    if let outcome = report.outcome(for: .runtimeColorScheme), let error = outcome.error {
        handleMigrationError(error, at: outcome.status)
    }

    try report.throwIfIncomplete()
}
