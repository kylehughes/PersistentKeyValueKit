// README samples: Quick Start.

import Combine
import Foundation

// MARK: - Stubs

nonisolated(unsafe) let userDefaults = UserDefaults.standard
nonisolated(unsafe) var cancellables = Set<AnyCancellable>()

func apply(_ runtimeColorScheme: RuntimeColorScheme) {
}

// MARK: - Samples

import PersistentKeyValueKit

nonisolated enum RuntimeColorScheme: String {
    case dark
    case light
    case system
}

extension RuntimeColorScheme: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}

import PersistentKeyValueKit

extension PersistentKeyProtocol where Self == PersistentKey<RuntimeColorScheme> {
    static var runtimeColorScheme: Self {
        Self("RuntimeColorScheme", defaultValue: .system)
    }
}

import PersistentKeyValueKit
import SwiftUI

struct SettingsView: View {
    @PersistentValue(.runtimeColorScheme)
    var runtimeColorScheme

    var body: some View {
        Picker("Appearance", selection: $runtimeColorScheme) {
            Text("System").tag(RuntimeColorScheme.system)
            Text("Light").tag(RuntimeColorScheme.light)
            Text("Dark").tag(RuntimeColorScheme.dark)
        }
    }
}

func readAndWrite() {
    let currentScheme = userDefaults.get(.runtimeColorScheme)
    userDefaults.set(.runtimeColorScheme, to: .dark)

    _ = currentScheme
}

func observeValues() async {
    for await runtimeColorScheme in userDefaults.values(for: .runtimeColorScheme) {
        apply(runtimeColorScheme)
    }
}

func observeWithCombine() {
    userDefaults.publisher(for: .runtimeColorScheme)
        .receive(on: DispatchQueue.main)
        .sink { runtimeColorScheme in
            apply(runtimeColorScheme)
        }
        .store(in: &cancellables)
}
