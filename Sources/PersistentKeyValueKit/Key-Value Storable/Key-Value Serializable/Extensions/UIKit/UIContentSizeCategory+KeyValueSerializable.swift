//
//  UIContentSizeCategory+KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/27/24.
//

#if canImport(UIKit) && !os(watchOS)

import Foundation
import UIKit

// MARK: - KeyValueSerializable Extension

extension UIContentSizeCategory: KeyValueSerializable, KeyValueSerializableAsRawRepresentable {
    // MARK: Public Typealiases
    
    public typealias Serialization = RawValue
}

#endif
