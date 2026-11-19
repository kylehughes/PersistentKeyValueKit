// README samples: registering defaults with UserDefaults.

import Foundation
import PersistentKeyValueKit

// MARK: - Stubs

nonisolated(unsafe) let userDefaults = UserDefaults.standard

extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    static var launchCount: Self {
        Self("LaunchCount", defaultValue: 0)
    }
}

// MARK: - Samples

userDefaults.register(.launchCount)
