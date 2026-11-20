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
final class ProfileViewController {
    let usernameLabel = Label()
    var cancellables = Set<AnyCancellable>()

    func handleChange(username: String) {
    }

    func publishValues() {
        UserDefaults.standard.publisher(for: .username)
            .receive(on: DispatchQueue.main)
            .sink { [usernameLabel] username in
                usernameLabel.text = username
            }
            .store(in: &cancellables)

        let usernameKey: PersistentKey<String> = .username
        usernameKey.publisher(in: UserDefaults.standard)
            .receive(on: DispatchQueue.main)
            .sink { [usernameLabel] username in
                usernameLabel.text = username
            }
            .store(in: &cancellables)
    }

    func publishChanges() {
        UserDefaults.standard.changesPublisher(for: .username)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] username in
                self?.handleChange(username: username)
            }
            .store(in: &cancellables)
    }
}
