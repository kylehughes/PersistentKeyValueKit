//
//  TestCodableStorable.swift
//  CodeMonkeyApple
//
//  Created by Kyle Hughes on 4/17/22.
//

import Foundation
import KeyValueKit

struct TestCodableStorable: Codable, Equatable, StorableAsCodable {
    static let random = TestCodableStorable(int: .random(in: 0 ... .max), string: UUID().uuidString)
    
    let int: Int
    let string: String
}
