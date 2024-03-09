//
//  TestRawRepresentableKeyValueStorable.swift
//  CodeMonkeyAppleTests
//
//  Created by Kyle Hughes on 4/17/22.
//

import KeyValueKit

enum TestRawRepresentableKeyValueStorable:
    String,
    Equatable,
    KeyValueStorableAsProxy,
    KeyValueSerializableAsRawRepresentable,
    KeyValuePersistible
{
    typealias Persistence = RawValue
    typealias Serialization = RawValue

    case caseOne
    case caseTwo = "CASE_TWO"
}
