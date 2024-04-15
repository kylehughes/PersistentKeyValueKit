//
//  UIContentSizeCategory+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

#if canImport(UIKit)

import UIKit

// MARK: - KeyValuePersistible Extension

extension UIContentSizeCategory: NewKeyValuePersistible {
    // MARK: Public Static Interface
    
    public static let persistentKeyValueRepresentation = ProxyPersistentKeyValueRepresentation<Self, RawValue>.rawValue
}

#endif
