// README samples: async and Combine observation.

import Combine
import Foundation
import PersistentKeyValueKit

// MARK: - Stubs

extension PersistentKeyProtocol where Self == PersistentKey<String> {
    static var username: Self {
        Self("Username", defaultValue: "")
    }
}

@MainActor
final class Label {
    var text: String?
}

let usernameLabel = Label()

nonisolated(unsafe) var cancellables = Set<AnyCancellable>()

func handleChange(username: String) {
}

func recordChange(username: String) {
}

// MARK: - Samples

@MainActor
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

@MainActor
func publishValues() {
    UserDefaults.standard.publisher(for: .username)
        .receive(on: DispatchQueue.main)
        .sink { username in
            usernameLabel.text = username
        }
        .store(in: &cancellables)

    let usernameKey: PersistentKey<String> = .username
    usernameKey.publisher(in: UserDefaults.standard)
        .receive(on: DispatchQueue.main)
        .sink { username in
            usernameLabel.text = username
        }
        .store(in: &cancellables)
}

func publishChanges() {
    UserDefaults.standard.changesPublisher(for: .username)
        .sink { username in
            handleChange(username: username)
        }
        .store(in: &cancellables)
}
