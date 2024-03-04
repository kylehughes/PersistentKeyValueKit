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
    
    public func adding<Value>(_ key: StoreKey<Value>) -> UserDefaultsRegistrationBuilder {
        var copy = self
        
        copy.registrations[key.id] = key.defaultValue.serialize()
        
        return copy
    }

    public func adding<Value>(_ key: StoreKey<Value?>) -> UserDefaultsRegistrationBuilder {
        var copy = self
        
        if let serialization = key.defaultValue.serialize() {
            copy.registrations[key.id] = serialization
        }
        
        return copy
    }
    
    public func adding<Value>(_ key: DebugStoreKey<Value>) -> UserDefaultsRegistrationBuilder {
        #if DEBUG
        var copy = self
        
        copy.registrations[key.id] = key.defaultValue.serialize()
        
        return copy
        #else
        self
        #endif
    }
    
    public func adding<Value>(_ key: DebugStoreKey<Value?>) -> UserDefaultsRegistrationBuilder {
        #if DEBUG
        var copy = self
        
        if let serialization = key.defaultValue.serialize() {
            copy.registrations[key.id] = serialization
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
