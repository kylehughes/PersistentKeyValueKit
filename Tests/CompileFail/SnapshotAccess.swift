import PersistentKeyValueKit

let store = InMemoryPersistentKeyValueStore()
_ = store.migrationEndpoint.snapshot(for: "key")
