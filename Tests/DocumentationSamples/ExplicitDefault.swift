// README samples: a non-optional key with an explicit default.

import PersistentKeyValueKit

// MARK: - Samples

extension PersistentKeyProtocol where Self == PersistentKey<Bool> {
    static var arePushNotificationsEnabled: Self {
        Self("ArePushNotificationsEnabled", defaultValue: true)
    }
}
