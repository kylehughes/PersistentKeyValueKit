//
//  DateKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/30/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class DateKeyValuePersistibleTests: AbstractKeyValuePersistibleTests<
    Date,
    TimeInterval,
    TimeInterval,
    TimeInterval
> {
    // MARK: AbstractKeyValuePersistibleTests Implementation

    override var expectations: [Expectation] {
        [
            Expectation(
                target: Date(timeIntervalSinceReferenceDate: 1_000_000),
                propertyListRepresentation: \.timeIntervalSinceReferenceDate,
                ubiquitousStoreRepresentation: \.timeIntervalSinceReferenceDate,
                userDefaultsRepresentation: \.timeIntervalSinceReferenceDate
            )
        ]
    }
}
