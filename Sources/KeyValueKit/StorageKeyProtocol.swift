//
//  StorageKeyProtocol.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 4/17/22.
//

import Foundation

public protocol StorageKeyProtocol: Identifiable where ID == String {
    // MARK: Associated Types
    
    associatedtype Value: Storable
    
    // MARK: Instance Interface
    
    var defaultValue: Value { get }
    var id: String { get }
    
    func get(from userDefaults: UserDefaults) -> Value
    func remove(from userDefaults: UserDefaults)
    func set(to newValue: Value, in userDefaults: UserDefaults)
    
    #if !os(watchOS)
    func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value
    func remove(from ubiquitousStore: NSUbiquitousKeyValueStore)
    func set(to newValue: Value, in ubiquitousStore: NSUbiquitousKeyValueStore)
    #endif
}
