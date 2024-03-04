//
//  StoreKeyObserver.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 6/13/22.
//

import Combine
import Foundation

/// This class, and the ``KeyValueStore`` functions it relies upon, implement the two known ways to observe
/// `UserDefaults` and `NSUbiquitousKeyValueStore`. It is likely that other ``KeyValueStore`` implementations can be
/// written under the same interface but that is not what it is optimized for. This lets us use ``StoredValue`` with
/// any type of ``KeyValueStore`` and simplifies many callsites that previously had to be duplicated between those two
/// known ``KeyValueStore`` implementations.
public class StoreKeyObserver<Key>: NSObject, ObservableObject where Key: StoreKeyProtocol {
    public let key: Key
    public let storage: KeyValueStore
    
    private var context: Int
    
    // MARK: Public Initialization
    
    public init(storage: KeyValueStore, key: Key) {
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
