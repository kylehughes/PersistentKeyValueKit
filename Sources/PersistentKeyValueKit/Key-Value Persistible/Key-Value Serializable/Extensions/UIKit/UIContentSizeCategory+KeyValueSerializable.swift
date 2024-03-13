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
    
    /// The type that this value can be serialized to and deserialized from.
    public typealias Serialization = RawValue
}

#endif
