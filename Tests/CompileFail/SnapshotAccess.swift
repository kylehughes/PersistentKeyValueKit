import PersistentKeyValueKit

let store = InMemoryPersistentKeyValueStore()
_ = try? store.migrationSnapshot(for: "key")
