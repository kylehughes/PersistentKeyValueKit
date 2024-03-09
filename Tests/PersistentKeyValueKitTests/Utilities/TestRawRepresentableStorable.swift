//
//  TestRawRepresentableKeyValueStorable.swift
//  CodeMonkeyAppleTests
//
//  Created by Kyle Hughes on 4/17/22.
//

import PersistentKeyValueKit

enum TestRawRepresentableKeyValueStorable:
    String,
    Equatable,
    KeyValueStorableAsProxy,
    KeyValueSerializableAsRawRepresentable,
    KeyValuePersistible
{
    typealias Storage = RawValue
    typealias Serialization = RawValue

    case caseOne
    case caseTwo = "CASE_TWO"
}
