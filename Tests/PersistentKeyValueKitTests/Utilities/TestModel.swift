//
//  TestModel.swift
//  KeyValueKitTests
//
//  Created by Kyle Hughes on 4/21/22.
//

import Foundation
import PersistentKeyValueKit

public struct TestModel: 
    Codable,
    Equatable,
    KeyValueStorableAsProxy,
    KeyValueSerializableAsCodable,
    KeyValuePersistible
{
    public typealias Storage = String
    public typealias Serialization = String
    
    public let id: UUID
    public let fullName: String
    public let emailAddress: String?
    
    // MARK: Public Static Interface
    
    public static var random: Self {
        TestModel(id: UUID(), fullName: UUID().uuidString, emailAddress: UUID().uuidString)
    }
}
