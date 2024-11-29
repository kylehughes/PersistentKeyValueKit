//
//  URLUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation

final class URLUserDefaultsTests: AbstractUserDefaultsTypeTests<URL> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [URL] {
        [
            URL(string: "https://kylehugh.es")!,
            URL(string: "https://example.com/path?query=value#fragment")!,
            URL(string: "file:///path/to/file.txt")!,
            URL(string: "data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==")!,
        ]
    }
}
