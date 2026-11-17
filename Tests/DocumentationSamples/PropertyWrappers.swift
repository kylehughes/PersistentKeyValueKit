// README samples: SwiftUI property wrapper and default store.

import PersistentKeyValueKit
import SwiftUI

// MARK: - Stubs

extension PersistentKeyProtocol where Self == PersistentDebugKey<Bool> {
    static var isAppStoreRatingEnabled: Self {
        Self("IsAppStoreRatingEnabled", debugDefaultValue: false, releaseDefaultValue: true)
    }
}

struct RootView: View {
    var body: some View {
        EmptyView()
    }
}

// MARK: - Samples

struct RatingSettingsView: View {
    @PersistentValue(.isAppStoreRatingEnabled)
    var isAppStoreRatingEnabled: Bool

    @PersistentValue(.isAppStoreRatingEnabled, store: .ubiquitous)
    var isSyncedRatingEnabled: Bool

    var body: some View {
        EmptyView()
    }
}

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .defaultPersistentKeyValueStore(.ubiquitous)
        }
    }
}
