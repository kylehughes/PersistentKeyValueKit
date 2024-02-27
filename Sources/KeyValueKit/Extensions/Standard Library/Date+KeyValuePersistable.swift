//
//  Date+KeyValuePersistable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/26/24.
//

import Foundation

// MARK: - KeyValuePersistable Extension

extension Date: KeyValuePersistable, KeyValuePersistableAsProxy {
    // MARK: Public Typealiases
    
    public typealias Persistence = TimeInterval
}
