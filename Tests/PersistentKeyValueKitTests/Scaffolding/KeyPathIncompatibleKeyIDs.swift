//
//  KeyPathIncompatibleKeyIDs.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

/// Returns valid `UserDefaults` key identifiers that key-value observation cannot observe, each unique to `function`
/// where its shape allows.
///
/// Registering key-value observation for the empty identifier, one whose period combines with the next scalar into
/// one `Character`, one containing a NUL character, or `valueForKey:` raises an exception or crashes. Key-value
/// observation registers an identifier that begins with `@` as a collection operator and never reports its changes.
func keyPathIncompatibleKeyIDs(uniqueTo function: String = #function) -> [String] {
    [
        "",
        ".\u{200D}",
        "\(function).\u{200D}",
        "\(function)\u{0}",
        "@count",
        "@user:\(function)",
        "@\u{301}:\(function)",
        "valueForKey:",
        "ValueForKey:",
    ]
}
