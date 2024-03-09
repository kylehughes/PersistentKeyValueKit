//
//  TestCodableKeyValueStorable.swift
//  CodeMonkeyApple
//
//  Created by Kyle Hughes on 4/17/22.
//

import Foundation
import PersistentKeyValueKit

struct TestCodableKeyValueStorable: 
    Codable,
    Equatable,
    KeyValueStorableAsProxy,
    KeyValueSerializableAsCodable,
    KeyValuePersistible
{
    typealias Persistence = String
    typealias Serialization = String
    
    static let random = TestCodableKeyValueStorable(int: .random(in: 0 ... .max), string: UUID().uuidString)
    
    let int: Int
    let string: String
}
