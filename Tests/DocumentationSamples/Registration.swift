// README samples: registering defaults with UserDefaults.

import Foundation
import PersistentKeyValueKit

// MARK: - Stubs

nonisolated(unsafe) let userDefaults = UserDefaults.standard

// MARK: - Samples

extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 1)
    }
}

userDefaults.register(.launchCount)
