//
//  TestModel.swift
//  KeyValueKitTests
//
//  Created by Kyle Hughes on 4/21/22.
//

import Foundation
import KeyValueKit

public struct TestModel: Codable, Equatable, KeyValuePersistableAsProxy, KeyValueSerializableAsCodable, KeyValueStorable {
    public typealias Persistence = String
    public typealias Serialization = String
    
    public let id: UUID
    public let fullName: String
    public let emailAddress: String?
    
    // MARK: Public Static Interface
    
    public static var random: Self {
        TestModel(id: UUID(), fullName: UUID().uuidString, emailAddress: UUID().uuidString)
    }
}
