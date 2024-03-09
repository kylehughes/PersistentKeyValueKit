//
//  Optional+KeyValuePersistible.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Optional: KeyValuePersistible where Wrapped: KeyValuePersistible {
    // NO-OP
}
