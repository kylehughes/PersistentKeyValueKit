//
//  UserDefaultsRegistrationBuilder.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/29/22.
//

import Foundation

public struct UserDefaultsRegistrationBuilder {
    private var registrations: [String: Any]
    
    // MARK: Public Initialization
    
    public init() {
        registrations = [:]
    }
    
    // MARK: Public Instance Interface
    
    public func adding<Value>(_ key: StorageKey<Value>) -> UserDefaultsRegistrationBuilder {
        var copy = self
        
        copy.registrations[key.id] = key.defaultValue.encodeForStorage()
        
        return copy
    }

    public func adding<Value>(_ key: StorageKey<Value?>) -> UserDefaultsRegistrationBuilder {
        var copy = self
        
        if let encodedValue = key.defaultValue.encodeForStorage() {
            copy.registrations[key.id] = encodedValue
        }
        
        return copy
    }
    
    public func adding<Value>(_ key: DebugStorageKey<Value>) -> UserDefaultsRegistrationBuilder {
        #if DEBUG
        var copy = self
        
        copy.registrations[key.id] = key.defaultValue.encodeForStorage()
        
        return copy
        #else
        self
        #endif
    }
    
    public func adding<Value>(_ key: DebugStorageKey<Value?>) -> UserDefaultsRegistrationBuilder {
        #if DEBUG
        var copy = self
        
        if let encodedValue = key.defaultValue.encodeForStorage() {
            copy.registrations[key.id] = encodedValue
        }
        
        return copy
        #else
        self
        #endif
    }
    
    public func build() -> [String: Any] {
        registrations
    }
}

// MARK: - Extension for UserDefaults

extension UserDefaults {
    // MARK: Public Instance Interface
    
    @inlinable
    public func register(builder: (UserDefaultsRegistrationBuilder) -> UserDefaultsRegistrationBuilder) {
        register(defaults: builder(.init()).build())
    }
}
