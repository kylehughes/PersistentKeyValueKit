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
        // Without `.compareNonliteral`, Core Foundation compares UTF-16 code units, including unpaired surrogates,
        // without copying them.
        guard lhs.isContiguousUTF8, rhs.isContiguousUTF8 else {
            return CFStringCompare(lhs as CFString, rhs as CFString, []) == .compareEqualTo
        }

        // Contiguous UTF-8 is valid Unicode, so its bytes are equal exactly when its UTF-16 code units are.
        return lhs.utf8.elementsEqual(rhs.utf8)
    }
}
