import PersistentKeyValueKit

let source = InMemoryPersistentKeyValueStore()
let destination = InMemoryPersistentKeyValueStore()
let old = PersistentKey("old", defaultValue: 0)
let new = PersistentKey("new", defaultValue: 0)
_ = try? source.copy([.key(old, to: new)], to: destination, onConflict: .overwriteDestination, tracking: .untracked)
