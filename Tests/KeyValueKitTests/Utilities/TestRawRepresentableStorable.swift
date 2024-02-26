//
//  TestRawRepresentableStorable.swift
//  CodeMonkeyAppleTests
//
//  Created by Kyle Hughes on 4/17/22.
//

import KeyValueKit

enum TestRawRepresentableStorable: String, Equatable, StorableAsRawRepresentable {
    case caseOne
    case caseTwo = "CASE_TWO"
}
