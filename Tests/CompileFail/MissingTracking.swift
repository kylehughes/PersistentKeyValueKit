import PersistentKeyValueKit

let source = InMemoryPersistentKeyValueStore()
let destination = InMemoryPersistentKeyValueStore()
let key = PersistentKey("key", defaultValue: 0)
_ = try? source.copy(key, to: destination, onConflict: .overwriteDestination)
