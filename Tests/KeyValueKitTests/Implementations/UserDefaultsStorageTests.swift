//
//  UserDefaultsStorageTests.swift
//  CodeMonkeyAppleTests
//
//  Created by Kyle Hughes on 3/28/22.
//

import Foundation
import KeyValueKit
import XCTest

final class UserDefaultsStorageTests: XCTestCase {
    private let storage = UserDefaults.standard
    
    // MARK: XCTestCase Implementation
    
    override func tearDown() async throws {
        storage.dictionaryRepresentation().keys.forEach(storage.removeObject)
    }
}

// MARK: - Tests for Built-In Types

extension UserDefaultsStorageTests {
    // MARK: Tests
    
    func test_bool() {
        KeyValueStorableTestHarness<Bool>(firstValue: true, secondValue: false, storage: storage).test()
    }
    
    func test_data() {
        KeyValueStorableTestHarness<Data>(
            firstValue: UUID().uuidString.data(using: .utf8)!,
            secondValue: UUID().uuidString.data(using: .utf8)!,
            storage: storage
        ).test()
    }
    
    func test_date() {
        KeyValueStorableTestHarness<Date>(
            firstValue: Date(timeIntervalSince1970: .random(in: 0 ... 100_000)),
            secondValue: Date(timeIntervalSince1970: .random(in: 0 ... 100_000)),
            storage: storage
        ).test()
    }
    
    func test_double() {
        KeyValueStorableTestHarness<Double>(
            firstValue: .random(in: 0...100_000),
            secondValue: .random(in: 0...100_000),
            storage: storage
        ).test()
    }
    
    func test_float() {
        KeyValueStorableTestHarness<Float>(
            firstValue: .random(in: 0...100_000),
            secondValue: .random(in: 0...100_000),
            storage: storage
        ).test()
    }
    
    func test_int() {
        KeyValueStorableTestHarness<Int>(
            firstValue: .random(in: 0...100_000),
            secondValue: .random(in: 0...100_000),
            storage: storage
        ).test()
    }
    
    func test_string() {
        KeyValueStorableTestHarness<String>(
            firstValue: UUID().uuidString,
            secondValue: UUID().uuidString,
            storage: storage
        ).test()
    }
    
    func test_stringArray() {
        KeyValueStorableTestHarness<[String]>(
            firstValue: [UUID().uuidString, UUID().uuidString, UUID().uuidString],
            secondValue: [UUID().uuidString, UUID().uuidString, UUID().uuidString],
            storage: storage
        ).test()
    }
    
    func test_url() {
        KeyValueStorableTestHarness<URL>(
            firstValue: URL(string: "https://kylehugh.es")!,
            secondValue: URL(string: "https://superhighway.info")!,
            storage: storage
        ).test()
    }
}

// MARK: - Tests for Complex Types

extension UserDefaultsStorageTests {
    // MARK: Functional Tests
    
    func test_codable() {
        KeyValueStorableTestHarness<TestCodableKeyValueStorable>(
            firstValue: .random,
            secondValue: .random,
            storage: storage
        ).test()
    }
    
    func test_rawRepresentable() {
        KeyValueStorableTestHarness<TestRawRepresentableKeyValueStorable>(
            firstValue: .caseOne,
            secondValue: .caseTwo,
            storage: storage
        ).test()
    }
    
    // MARK: Performance Metrics
    
    func test_perf_codable_get() {
        let model = TestModel.random
    
        let modelKey = PersistentKey<TestModel?>(id: UUID().uuidString, defaultValue: nil)
        
        storage.set(modelKey, to: model)
        
        measure(metrics: [XCTClockMetric()]) {
            _ = storage.get(modelKey)
        }
    }
    
    func test_perf_codable_set() {
        let model = TestModel.random
        
        let modelKey = PersistentKey<TestModel?>(id: UUID().uuidString, defaultValue: nil)
        
        measure(metrics: [XCTClockMetric()]) {
            storage.set(modelKey, to: model)
        }
    }
    
    func test_perf_multipleKeys_get() {
        let model = TestModel.random
        
        let emailAddressKey = PersistentKey<String?>(id: UUID().uuidString, defaultValue: nil)
        let fullNameKey = PersistentKey<String?>(id: UUID().uuidString, defaultValue: nil)
        let idKey = PersistentKey<UUID?>(id: UUID().uuidString, defaultValue: nil)
        
        storage.set(emailAddressKey, to: model.emailAddress)
        storage.set(fullNameKey, to: model.fullName)
        storage.set(idKey, to: model.id)
        
        measure(metrics: [XCTClockMetric()]) {
            _ = storage.get(emailAddressKey)
            _ = storage.get(fullNameKey)
            _ = storage.get(idKey)
        }
    }
    
    func test_perf_multipleKeys_set() {
        let model = TestModel.random
        
        let emailAddressKey = PersistentKey<String?>(id: UUID().uuidString, defaultValue: nil)
        let fullNameKey = PersistentKey<String?>(id: UUID().uuidString, defaultValue: nil)
        let idKey = PersistentKey<UUID?>(id: UUID().uuidString, defaultValue: nil)
        
        measure(metrics: [XCTClockMetric()]) {
            storage.set(emailAddressKey, to: model.emailAddress)
            storage.set(fullNameKey, to: model.fullName)
            storage.set(idKey, to: model.id)
        }
    }
}
