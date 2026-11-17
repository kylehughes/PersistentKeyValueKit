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
}

// MARK: - Samples

func copyToAppGroup() throws {
    guard let destination = UserDefaults.migratable(suiteName: "group.example.app") else {
        return
    }

    let report = try UserDefaults.standard.copy(
        [.runtimeColorScheme, .launchCount],
        to: destination,
        onConflict: .overwriteDestination,
        tracking: .untracked
    )

    _ = report
}

func moveToAppGroup(destination: UserDefaults) throws {
    let report = try UserDefaults.standard.move(
        [.runtimeColorScheme],
        to: destination,
        onConflict: .keepBoth,
        tracking: .once(id: "app-group-preferences-v1", recordedIn: destination)
    )

    if !report.isComplete {
        // Inspect report.outcomes and report.completion before retrying.
    }
}

func moveToAppGroupOnce() throws {
    guard let destination = UserDefaults.migratable(suiteName: "group.example.app") else {
        return
    }

    let report = try UserDefaults.standard.move(
        [.runtimeColorScheme, .launchCount],
        to: destination,
        onConflict: .keepBoth,
        tracking: .once(id: "app-group-preferences-v1", recordedIn: destination)
    )

    _ = report
}
