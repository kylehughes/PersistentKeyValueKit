// README samples: an optional key whose default is nil.

import PersistentKeyValueKit

// MARK: - Samples

extension PersistentKeyProtocol where Self == PersistentKey<Bool?> {
    static var arePushNotificationsEnabled: Self {
        Self("ArePushNotificationsEnabled", defaultValue: nil)
    }
}
