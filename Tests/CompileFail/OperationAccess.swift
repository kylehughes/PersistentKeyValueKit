import PersistentKeyValueKit

let store = InMemoryPersistentKeyValueStore()
_ = store.migrationEndpoint.commitWrite()
