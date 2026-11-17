import Foundation

/// Returns a suite name that is stable across runs and unique to the calling test, with its domain cleared.
///
/// `UserDefaults` leaves a preferences file behind for every suite name, so unique-per-run names accumulate files
/// forever. Stable names reuse the same file. The domain is cleared up front in case a previous run crashed; tests
/// still clear it again when they finish.
///
/// - Parameters:
///   - prefix: The test class and any discriminator for tests that need several suites.
///   - function: The calling test, which keeps names unique between tests.
func stableSuiteName(_ prefix: String, function: String = #function) -> String {
    let name = "\(prefix).\(function)"

    UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    UserDefaults(suiteName: name.lowercased())?.removePersistentDomain(forName: name.lowercased())

    return name
}
