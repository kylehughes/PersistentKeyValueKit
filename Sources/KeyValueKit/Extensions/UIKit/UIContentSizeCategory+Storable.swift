//
//  UIContentSizeCategory+Storable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 11/30/22.
//

#if canImport(UIKit) && !os(watchOS)

import Foundation
import UIKit

extension UIContentSizeCategory: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self
}

#endif
