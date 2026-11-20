//
//  FoundationKeyIdentifiers.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/18/26.
//

import Foundation
import ObjectiveC

// MARK: - AccessObservingString Definition

/// An immutable string whose character accessors call ``onAccess`` before reading its contents.
///
/// Swift bridges an `NSString` subclass lazily, so hashing or comparing a `String` bridged from it, or reading its
/// UTF-16 code units, calls these accessors.
final class AccessObservingString: NSString, @unchecked Sendable {
    private let lock = NSLock()
    private var contents: NSString = ""
    private var storedOnAccess: (@Sendable () -> Void)?

    // MARK: Internal Static Interface

    /// Returns a string with the given contents, with no access callback.
    static func make(_ contents: String) -> AccessObservingString {
        let string = AccessObservingString()
        string.contents = contents as NSString

        return string
    }

    // MARK: Internal Instance Interface

    /// The code to run on every character access, or `nil` to run none.
    var onAccess: (@Sendable () -> Void)? {
        get {
            lock.withLock {
                storedOnAccess
            }
        }
        set {
            lock.withLock {
                storedOnAccess = newValue
            }
        }
    }

    // MARK: NSString Implementation

    override var length: Int {
        onAccess?()

        return contents.length
    }

    override func character(at index: Int) -> unichar {
        onAccess?()

        return contents.character(at: index)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        self
    }

    override func getCharacters(_ buffer: UnsafeMutablePointer<unichar>, range: NSRange) {
        onAccess?()

        contents.getCharacters(buffer, range: range)
    }
}

// MARK: - Unpaired Surrogate Identifiers

/// Returns three identifiers that Foundation stores keep as different keys, although Swift reports the same UTF-16
/// code units for them: `prefix` followed by the unpaired high surrogate U+D83E, by the unpaired high surrogate U+D83D,
/// and by U+FFFD.
///
/// The first two are bridged from the `NSString`s that truncating "🦊" and "🚀" with `NSString.substring(to:)`
/// produces, and Swift's `utf16` view reports U+FFFD for their unpaired surrogates. The third is a native Swift string.
func unpairedSurrogateKeyIDs(_ prefix: String) -> [String] {
    let truncatedIDs = ["\u{1F98A}", "\u{1F680}"].map { emoji in
        let string = (prefix + emoji) as NSString

        return string.substring(to: string.length - 1)
    }

    return truncatedIDs + [prefix + "\u{FFFD}"]
}

// MARK: - Release-Observing Identifiers

/// Returns `contents` bridged from an immutable `NSString` that calls `onRelease` when it is deallocated.
///
/// The returned `String` is backed by that object, so whichever reference to the identifier is released last, such as
/// a store's, runs `onRelease`. Call this inside an `autoreleasepool` so that no autoreleased reference outlives the
/// caller's.
func releaseObservingKeyID(_ contents: String, onRelease: @escaping @Sendable () -> Void) -> String {
    let codeUnits = Array(contents.utf16)
    let string = NSString(characters: codeUnits, length: codeUnits.count)

    objc_setAssociatedObject(
        string,
        &releaseObserverAssociationKey,
        ReleaseObserver(onRelease: onRelease),
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )

    return string as String
}

nonisolated(unsafe) private var releaseObserverAssociationKey: UInt8 = 0

/// Calls a closure when it is deallocated.
private final class ReleaseObserver {
    private let onRelease: @Sendable () -> Void

    init(onRelease: @escaping @Sendable () -> Void) {
        self.onRelease = onRelease
    }

    deinit {
        onRelease()
    }
}
