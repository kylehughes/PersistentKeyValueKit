//
//  Optional+OptionalElement.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/19/26.
//

import Foundation

// MARK: - OptionalElement Definition

/// An `Optional`, used to constrain conformances to collections of optionals and to find a `nil` value at any level of
/// nesting.
protocol OptionalElement {
    associatedtype Wrapped

    var optionalValue: Wrapped? { get }
}

extension OptionalElement {
    /// The wrapped value, if any, as `Any`.
    var wrappedObject: Any? {
        optionalValue.map {
            $0 as Any
        }
    }
}

// MARK: - OptionalElement Extension

extension Optional: OptionalElement {
    var optionalValue: Wrapped? {
        self
    }
}
