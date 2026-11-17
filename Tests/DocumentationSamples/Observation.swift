// README samples: async and Combine observation.

import Foundation
import PersistentKeyValueKit

// MARK: - Stubs

extension PersistentKeyProtocol where Self == PersistentKey<String> {
    static var username: Self {
        Self("Username", defaultValue: "")
    }
}

final class Label {
    var text: String?
}

nonisolated(unsafe) let usernameLabel = Label()

func handleChange(username: String) {
}

func recordChange(username: String) {
}

// MARK: - Samples

func observeValues() async {
    for await username in UserDefaults.standard.values(for: .username) {
        usernameLabel.text = username
    }

    let usernameKey: PersistentKey<String> = .username
    for await username in usernameKey.values(in: UserDefaults.standard) {
        usernameLabel.text = username
    }
}

func observeChanges() async {
    for await username in UserDefaults.standard.changes(for: .username) {
        handleChange(username: username)
    }
}

func observeBufferedChanges() async {
    for await username in UserDefaults.standard.changes(for: .username, bufferingPolicy: .unbounded) {
        recordChange(username: username)
    }
}

func publishValues() {
    let cancellable = UserDefaults.standard.publisher(for: .username)
        .sink { username in
            usernameLabel.text = username
        }

    let usernameKey: PersistentKey<String> = .username
    let keyCancellable = usernameKey.publisher(in: UserDefaults.standard)
        .sink { username in
            usernameLabel.text = username
        }

    _ = (cancellable, keyCancellable)
}

func publishChanges() {
    let cancellable = UserDefaults.standard.changesPublisher(for: .username)
        .sink { username in
            handleChange(username: username)
        }

    _ = cancellable
}
