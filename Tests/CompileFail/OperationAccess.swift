import PersistentKeyValueKit

let store = InMemoryPersistentKeyValueStore()
_ = store.commitMigrationWrite
