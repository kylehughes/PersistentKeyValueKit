//
//  LiteralKeyID.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/18/26.
//

import Foundation

/// The literal identity of a key identifier: the UTF-16 code units by which Foundation stores compare keys.
///
/// Swift `String` equality treats canonically equivalent spellings, such as composed and decomposed "café", as equal,
/// while Foundation stores keep them as different keys. An identifier bridged from an `NSString` can also contain
/// unpaired surrogates, such as one truncated in the middle of an emoji by `NSString.substring(to:)`. Its `utf16` view
/// reports U+FFFD for each of them, so distinct Foundation keys would read the same code units; these functions read
/// or compare that identifier's code units through the `NSString` instead.
///
/// Reading or comparing the code units of an identifier bridged from an `NSString` calls the object's methods, which
/// can run arbitrary code, such as a subclass's character accessor that accesses a store. Code that compares
/// identifiers with a lock held therefore reads them first with ``codeUnits(of:)``, without the lock, and compares the
/// results.
@usableFromInline
internal enum LiteralKeyID {
    // MARK: Internal Static Interface

    /// Returns the UTF-16 code units of `keyID`, which name the same Foundation store key exactly when they are equal.
    @usableFromInline
    internal static func codeUnits(of keyID: String) -> [UInt16] {
        // Contiguous UTF-8 is valid Unicode, so its UTF-16 view is exact. Any other identifier is bridged from an
        // `NSString`, which can hold unpaired surrogates.
        guard !keyID.isContiguousUTF8 else {
            return Array(keyID.utf16)
        }

        let string = keyID as NSString
        var codeUnits = [UInt16](repeating: 0, count: string.length)
        string.getCharacters(&codeUnits, range: NSRange(location: 0, length: codeUnits.count))

        return codeUnits
    }

    /// Feeds the UTF-16 code units of `keyID` into `hasher`, so identifiers that ``match(_:_:)`` hash equally.
    @usableFromInline
    internal static func hash(_ keyID: String, into hasher: inout Hasher) {
        guard keyID.isContiguousUTF8 else {
            for codeUnit in codeUnits(of: keyID) {
                hasher.combine(codeUnit)
            }

            return
        }

        for codeUnit in keyID.utf16 {
            hasher.combine(codeUnit)
        }
    }

    /// Returns whether two key identifiers name the same Foundation store key.
    @usableFromInline
    internal static func match(_ lhs: String, _ rhs: String) -> Bool {
        switch (lhs.isContiguousUTF8, rhs.isContiguousUTF8) {
        case (true, true):
            // Contiguous UTF-8 is valid Unicode, so its bytes are equal exactly when its UTF-16 code units are.
            return lhs.utf8.elementsEqual(rhs.utf8)
        case (true, false):
            return match(native: lhs, foundation: rhs)
        case (false, true):
            return match(native: rhs, foundation: lhs)
        case (false, false):
            // Without `.compareNonliteral`, Core Foundation compares UTF-16 code units, including unpaired
            // surrogates, without copying them.
            return CFStringCompare(lhs as CFString, rhs as CFString, []) == .compareEqualTo
        }
    }

    // MARK: Private Static Interface

    /// The number of code units read from a Foundation string at a time when it has no contiguous UTF-16 buffer.
    private static let chunkLength = 64

    /// Returns whether the contiguous UTF-8 string `native` and the string `foundation` bridged from an `NSString` have
    /// the same UTF-16 code units.
    ///
    /// Core Foundation compares a Swift-native string through its bridged object, which is slow for long identifiers
    /// that share a prefix, so this compares the native string's UTF-16 view with the Foundation string's code units
    /// directly, without copying them.
    private static func match(native: String, foundation: String) -> Bool {
        let string = foundation as NSString
        let length = string.length

        // Core Foundation exposes its character buffer only when the string stores UTF-16.
        if let characters = CFStringGetCharactersPtr(string) {
            return withExtendedLifetime(string) {
                native.utf16.elementsEqual(UnsafeBufferPointer(start: characters, count: length))
            }
        }

        // Any other string, such as an 8-bit Core Foundation string or an `NSString` subclass, copies its code units.
        return withUnsafeTemporaryAllocation(of: UInt16.self, capacity: chunkLength) { chunk in
            var nativeCodeUnits = native.utf16.makeIterator()
            var location = 0

            while location < length {
                let count = min(chunk.count, length - location)

                string.getCharacters(chunk.baseAddress!, range: NSRange(location: location, length: count))

                for index in 0 ..< count {
                    guard nativeCodeUnits.next() == chunk[index] else {
                        return false
                    }
                }

                location += count
            }

            return nativeCodeUnits.next() == nil
        }
    }
}
