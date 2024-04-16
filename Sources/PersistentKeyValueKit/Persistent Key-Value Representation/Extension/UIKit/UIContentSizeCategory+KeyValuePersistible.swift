//
//  UIContentSizeCategory+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

#if canImport(UIKit)

import UIKit

// MARK: - KeyValuePersistible Extension

extension UIContentSizeCategory: KeyValuePersistible {
    // MARK: Public Static Interface
    
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawValuePersistentKeyValueRepresentation()
    }
}

#endif
