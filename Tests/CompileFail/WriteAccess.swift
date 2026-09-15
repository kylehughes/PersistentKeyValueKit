import PersistentKeyValueKit

let store = InMemoryPersistentKeyValueStore()
_ = store.migrationEndpoint.prepareWrite()
