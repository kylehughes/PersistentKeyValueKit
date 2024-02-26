//
//  UIContentSizeCategory+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 11/30/22.
//

#if canImport(UIKit) && !os(watchOS)

import Foundation
import UIKit

extension UIContentSizeCategory: KeyValueStorable {
    // MARK: Public Typealiases
    
    public typealias KeyValueStorableValue = Self
}

#endif
