//
//  UIContentSizeCategory+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/27/24.
//

#if canImport(UIKit) && !os(watchOS)

import Foundation
import UIKit

// MARK: - KeyValueStorable Extension

extension UIContentSizeCategory: KeyValueStorable, KeyValueStorableAsProxy {
    // MARK: Public Typealiases
    
    /// The type that values of this type are stored as in a ``PersistentKeyValueStore``.
    public typealias Storage = RawValue
}

#endif
