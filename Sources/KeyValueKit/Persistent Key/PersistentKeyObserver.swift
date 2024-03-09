//
//  PersistentKeyObserver.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 6/13/22.
//

import Combine
import Foundation

/// This class, and the ``PersistentKeyValueStore`` functions it relies upon, implement the two known ways to observe
/// `UserDefaults` and `NSUbiquitousKeyValueStore`. It is likely that other ``PersistentKeyValueStore`` implementations 
/// can be written under the same interface but that is not what it is optimized for. This lets us use
/// ``PersistentValue`` with  any type of ``PersistentKeyValueStore`` and simplifies many callsites that previously had
/// to be duplicated between those two known ``PersistentKeyValueStore`` implementations.
public class PersistentKeyObserver<Key>: NSObject, ObservableObject where Key: PersistentKeyProtocol {
    public let key: Key
    public let storage: any PersistentKeyValueStore
    
    private var context: Int
    
    // MARK: Public Initialization
    
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
    
    private func objectWillChange() {
        Task {
            await MainActor.run {
                objectWillChange.send()
            }
        }
    }
}