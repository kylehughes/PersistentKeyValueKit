import PersistentKeyValueKit

let store = InMemoryPersistentKeyValueStore()
_ = try! store.migrationEndpoint.snapshot(for: "key")
