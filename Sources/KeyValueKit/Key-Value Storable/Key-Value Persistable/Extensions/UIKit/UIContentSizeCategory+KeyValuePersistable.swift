//
//  UIContentSizeCategory+KeyValuePersistable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/27/24.
//

#if canImport(UIKit) && !os(watchOS)

import Foundation
import UIKit

// MARK: - KeyValuePersistable Extension

extension UIContentSizeCategory: KeyValuePersistable, KeyValuePersistableAsProxy {
    // MARK: Public Typealiases
    
    /// The type that the conforming type is persisted as in a ``PersistentKeyValueStore``.
    public typealias Persistence = RawValue
}

#endif
