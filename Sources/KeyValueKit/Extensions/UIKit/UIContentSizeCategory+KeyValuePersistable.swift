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
    
    public typealias Persistence = RawValue
}

#endif
