import PersistentKeyValueKit

let store = InMemoryPersistentKeyValueStore()
_ = try? store.prepareMigrationWrite(0, for: PersistentKey("key", defaultValue: 0))
