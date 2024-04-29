//
//  PersistentKeyObserver.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 6/13/22.
//

import Combine
import Foundation

/// An observer for a key in a ``PersistentKeyValueStore``.
///
/// This class, and the ``PersistentKeyValueStore`` functions it relies upon, implement the two known ways to observe
/// `UserDefaults` and `NSUbiquitousKeyValueStore`. It is likely that other ``PersistentKeyValueStore`` implementations 
/// can be written under the same interface but that is not what it is optimized for. This lets us use
/// ``PersistentValue`` with  any type of ``PersistentKeyValueStore`` and simplifies many callsites that previously had
/// to be duplicated between those two known ``PersistentKeyValueStore`` implementations.
public class PersistentKeyObserver<Key>: NSObject, ObservableObject where Key: PersistentKeyProtocol {
    /// The key being observed.
    public let key: Key

    /// The store that the key is being observed in.
    public let storage: any PersistentKeyValueStore
    
    /// The context for the key-value observation.
    private var context: Int
    
    // MARK: Public Initialization
    
    /// Creates a new observer for the given key in the given store.
    ///
    /// - Parameter storage: The store to observe the key in.
    /// - Parameter key: The key to observe.
    public init(storage: some PersistentKeyValueStore, key: Key) {
        self.storage = storage
        self.key = key
        
        context = 0
        
        super.init()
        
        storage.register(observer: self, for: key, with: &context) { [weak self] in
            self?.objectWillChange()
        }
    }
    
    deinit {
        storage.deregister(observer: self, for: key, with: &context)
    }
    
    // MARK: Public Instance Interface
    
    /// The value of the key in the store.
    @inlinable
    public var value: Key.Value {
        get {
            storage.get(key)
        }
        set {
            objectWillChange.send()
            
            storage.set(key, to: newValue)
        }
    }
    
    // MARK: NSObject Implementation
    
    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        objectWillChange()
    }
    
    // MARK: Private Instance Interface
    
    /// Sends the `objectWillChange` signal on the main actor.
    private func objectWillChange() {
        Task {
            await MainActor.run {
                objectWillChange.send()
            }
        }
    }
}
