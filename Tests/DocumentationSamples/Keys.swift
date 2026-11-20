// README samples: keys and debug keys.

import Foundation
import PersistentKeyValueKit

// MARK: - Stubs

nonisolated(unsafe) let userDefaults = UserDefaults.standard
let listID = "list"

func applyLayout(id: String) {
}

// MARK: - Samples

extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 0)
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<String?> {
    static func selectedLayoutID(forListID listID: String) -> Self {
        Self("\(listID)::SelectedLayoutID", defaultValue: nil)
    }
}

func useKeys() {
    userDefaults.set(.launchCount, to: 1)

    if let layoutID = NSUbiquitousKeyValueStore.default.get(.selectedLayoutID(forListID: listID)) {
        applyLayout(id: layoutID)
    }
}

extension PersistentKeyProtocol where Self == PersistentDebugKey<Bool> {
    static var isAppStoreRatingEnabled: Self {
        Self(
            "IsAppStoreRatingEnabled",
            debugDefaultValue: false,
            releaseDefaultValue: true
        )
    }
}

userDefaults.set(.isAppStoreRatingEnabled, to: false)
let isRatingEnabled = userDefaults.get(.isAppStoreRatingEnabled) // Debug: false unless a higher-priority defaults value overrides it; Release: true
