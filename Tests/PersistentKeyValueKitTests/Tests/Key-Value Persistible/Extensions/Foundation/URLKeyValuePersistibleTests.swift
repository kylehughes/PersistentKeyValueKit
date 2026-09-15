//
//  URLKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/30/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class URLKeyValuePersistibleTests: AbstractKeyValuePersistibleTests<URL, String, String, URL> {
    // MARK: AbstractKeyValuePersistibleTests Implementation
    
    override public var expectations: [Expectation] {
        targets.map {
            Expectation(
                target: $0,
                propertyListRepresentation: \.absoluteString,
                ubiquitousStoreRepresentation: \.absoluteString,
                userDefaultsRepresentation: \.self
            )
        }
    }
    
    // MARK: Instance Implementation

    var targets: [URL] {
        [
            URL(string: "https://kylehugh.es")!
        ]
    }

    @available(watchOS 9.0, *)
    @MainActor
    func testUbiquitousStoreReadsLegacyURLObject() {
        let store = MockUbiquitousKeyValueStore()
        let value = URL(string: "https://kylehugh.es/legacy")!
        store.set(value, forKey: "url")

        XCTAssertEqual(URL.get("url", from: store), value)
    }

    @available(watchOS 9.0, *)
    @MainActor
    func testUbiquitousStoreSetterStoresAbsoluteString() {
        let store = MockUbiquitousKeyValueStore()
        let webURL = URL(string: "https://kylehugh.es/web")!
        URL.set("web", to: webURL, in: store)
        XCTAssertEqual(store.object(forKey: "web") as? String, webURL.absoluteString)

        let fileURL = URL(fileURLWithPath: "/tmp/file")
        URL.set("file", to: fileURL, in: store)
        XCTAssertEqual(store.object(forKey: "file") as? String, fileURL.absoluteString)
    }
}
