import PersistentKeyValueKit

let store = InMemoryPersistentKeyValueStore()
_ = try! store.migrationEndpoint.identity
