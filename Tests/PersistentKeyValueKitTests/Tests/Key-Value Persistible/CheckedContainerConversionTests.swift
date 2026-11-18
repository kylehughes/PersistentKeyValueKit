//
//  CheckedContainerConversionTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies how checked conversion, which migration and registration use, converts property-list containers.
///
/// Built-in representations convert their elements through checked conversion directly, on any thread, and rethrow the
/// first underlying error. Other representations are converted through their container methods exactly as they are
/// implemented, and checked conversion leaves ordinary reads unchanged.
final class CheckedContainerConversionTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.CheckedContainerConversion", function: name)
        userDefaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }
}

// MARK: - Thread Independence Tests

extension CheckedContainerConversionTests {
    func test_move_builtInNestedDictionary_failsOnWorkerThread() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [[String: Int]]())
        let stored: [[String: Any]] = [["good": 7, "bad": "broken"]]
        // UserDefaults is thread-safe.
        let source = UncheckedSendableBox(userDefaults!)

        source.value.set(stored, forKey: key.id)

        for runsOnWorkerThread in [false, true] {
            let destination = InMemoryPersistentKeyValueStore()
            let report = try perform(onWorkerThread: runsOnWorkerThread) {
                try source.value.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
            }

            XCTAssertEqual(report.outcomes.map(\.status), [.failed(.decode)], "\(runsOnWorkerThread)")
            XCTAssertEqual(
                report.outcomes.first?.error as? PersistentKeyValueConversionError,
                .invalidStorageValue,
                "\(runsOnWorkerThread)"
            )
            XCTAssertEqual(userDefaults.array(forKey: key.id)?.count, 1, "\(runsOnWorkerThread)")
            XCTAssertNil(destination.object(forKey: key.id), "\(runsOnWorkerThread)")
        }
    }

    func test_move_builtInNestedDictionaryWithCollidingKeys_failsOnWorkerThread() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [[String: Int]]())
        let native = NSMutableDictionary()

        native["caf\u{E9}" as NSString] = 5
        native["cafe\u{301}" as NSString] = 7

        // UserDefaults is thread-safe.
        let source = UncheckedSendableBox(userDefaults!)
        let destination = InMemoryPersistentKeyValueStore()

        source.value.set(NSArray(object: native), forKey: key.id)

        let report = try perform(onWorkerThread: true) {
            try source.value.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
        }

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.decode)])
        XCTAssertEqual(((userDefaults.array(forKey: key.id) as NSArray?)?.firstObject as? NSDictionary)?.count, 2)
        XCTAssertNil(destination.object(forKey: key.id))
    }

    func test_move_customArrayHookThatDropsEntries_dropsThemOnEveryThread() throws {
        let stored: [[String: Any]] = [["good": 7, "bad": "broken"]]
        let inlineKey = PersistentKey("key:\(#function).inline", defaultValue: [InlineHookRow]())
        let workerKey = PersistentKey("key:\(#function).worker", defaultValue: [WorkerThreadHookRow]())
        let destination = InMemoryPersistentKeyValueStore()

        userDefaults.set(stored, forKey: inlineKey.id)
        userDefaults.set(stored, forKey: workerKey.id)

        // The hooks decode each row with the ordinary dictionary read, which omits the undecodable entry. Checked
        // conversion calls a custom hook as written, so migration keeps what the hook returns, whichever thread it
        // decodes on.
        let report = try userDefaults.move(
            [inlineKey, workerKey],
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved, .moved])
        XCTAssertEqual(destination.get(inlineKey).map(\.counts), [["good": 7]])
        XCTAssertEqual(destination.get(workerKey).map(\.counts), [["good": 7]])
    }

    func test_checkedDecode_customArrayHookOnWorkerThread_throwsWhenHookFails() {
        let representation = [WorkerThreadHookRow].persistentKeyValueRepresentation

        XCTAssertEqual(
            try representation.decode(storageObject: [["a": 1]], format: .propertyList).map(\.counts),
            [["a": 1]]
        )
        XCTAssertThrowsError(try representation.decode(storageObject: ["not a dictionary"], format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
    }
}

// MARK: - Ordinary Read Tests

extension CheckedContainerConversionTests {
    func test_move_ordinaryReadDuringCheckedDecode_keepsOrdinaryBehavior() throws {
        let settingsKey = PersistentKey("key:\(#function).settings", defaultValue: [["default": -1]])
        let key = PersistentKey("key:\(#function)", defaultValue: [SettingsReadingValue]())
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = SettingsReadRecorder(userDefaults: userDefaults, key: settingsKey)
        let stored: [[String: Any]] = [["good": 7, "bad": "broken"]]

        userDefaults.set(stored, forKey: settingsKey.id)
        userDefaults.set([1], forKey: key.id)

        let report = try SettingsReadRecorder.$current.withValue(recorder) {
            try userDefaults.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
        }

        XCTAssertEqual(recorder.waitForTaskRead(), [["good": 7]])
        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(recorder.synchronousReads, [[["good": 7]]])
        XCTAssertEqual(userDefaults.get(settingsKey), [["good": 7]])
    }
}

// MARK: - Recursion Tests

extension CheckedContainerConversionTests {
    func test_checkedConversion_recursiveArrayCodecWithInvalidLeaf_convertsEachLevelOnce() {
        let depth = 20
        var node = RecursiveListNode.invalid
        var object: Any = "invalid"

        for _ in 0 ..< depth {
            node = .branch([node])
            object = [object]
        }

        let counter = RecursiveListNode.Representation.counter
        let representation = RecursiveListNode.persistentKeyValueRepresentation

        counter.reset()

        XCTAssertThrowsError(try representation.encode(node, format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .encodingFailed)
        }
        XCTAssertThrowsError(try representation.decode(storageObject: object, format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
        XCTAssertLessThanOrEqual(counter.encodes, 2 * (depth + 1))
        XCTAssertLessThanOrEqual(counter.decodes, 2 * (depth + 1))
    }

    func test_checkedConversion_recursiveDictionaryCodecWithInvalidLeaf_convertsEachLevelOnce() {
        let depth = 20
        var node = RecursiveMapNode.invalid
        var object: Any = "invalid"

        for _ in 0 ..< depth {
            node = .branch(["child": node])
            object = ["child": object]
        }

        let counter = RecursiveMapNode.Representation.counter
        let representation = RecursiveMapNode.persistentKeyValueRepresentation

        counter.reset()

        XCTAssertThrowsError(try representation.encode(node, format: .propertyList))
        XCTAssertThrowsError(try representation.decode(storageObject: object, format: .propertyList))
        XCTAssertLessThanOrEqual(counter.encodes, 2 * (depth + 1))
        XCTAssertLessThanOrEqual(counter.decodes, 2 * (depth + 1))
    }

    func test_checkedConversion_recursiveArrayCodec_roundTrips() throws {
        let node = RecursiveListNode.branch([.branch([]), .branch([.branch([])])])
        let representation = RecursiveListNode.persistentKeyValueRepresentation

        let object = try XCTUnwrap(try representation.encode(node, format: .propertyList))

        XCTAssertEqual((object as? [[Any]])?.map(\.count), [0, 1])
        XCTAssertEqual(try representation.decode(storageObject: object, format: .propertyList), node)
    }
}

// MARK: - Error Identity Tests

extension CheckedContainerConversionTests {
    func test_checkedEncode_builtInContainers_rethrowFirstCoderErrorAtAnyPosition() {
        for amounts in [[Double.nan, 2], [2, Double.nan]] {
            let payloads = amounts.map(CodedPayload.init)

            assertEncodingError([CodedPayload].persistentKeyValueRepresentation, payloads, "\(amounts)")
            assertEncodingError([CodedPayload?].persistentKeyValueRepresentation, payloads, "\(amounts)")
            assertEncodingError([[CodedPayload]].persistentKeyValueRepresentation, [payloads], "\(amounts)")
            assertEncodingError(
                [String: CodedPayload].persistentKeyValueRepresentation,
                ["a": CodedPayload(amount: .nan)],
                "\(amounts)"
            )
            assertEncodingError(
                [String: [CodedPayload]].persistentKeyValueRepresentation,
                ["a": payloads],
                "\(amounts)"
            )
        }
    }

    func test_checkedDecode_builtInContainers_rethrowFirstCoderErrorAtAnyPosition() throws {
        let valid = try JSONEncoder().encode(CodedPayload(amount: 1))
        let invalid = Data("not json".utf8)

        for objects in [[invalid, valid], [valid, invalid]] {
            assertDecodingError([CodedPayload].persistentKeyValueRepresentation, objects, "\(objects)")
            assertDecodingError([CodedPayload?].persistentKeyValueRepresentation, objects, "\(objects)")
            assertDecodingError([[CodedPayload]].persistentKeyValueRepresentation, [objects], "\(objects)")
            assertDecodingError([String: CodedPayload].persistentKeyValueRepresentation, ["a": invalid], "")
            assertDecodingError([String: CodedPayload?].persistentKeyValueRepresentation, ["a": invalid], "")
        }
    }

    func test_checkedDecode_builtInProxyContainers_rethrowFirstElementErrorInInputOrder() throws {
        let malformed = Data("invalid JSON".utf8)
        let valid = try JSONEncoder().encode(CodedPayload(amount: 1))

        XCTAssertEqual(
            try [OuterPayload].persistentKeyValueRepresentation.decode(storageObject: [valid], format: .propertyList),
            [OuterPayload(payload: CodedPayload(amount: 1))]
        )
        XCTAssertEqual(
            try [ProxiedCount?].persistentKeyValueRepresentation.decode(storageObject: [1, 2], format: .propertyList),
            [ProxiedCount(1), ProxiedCount(2)]
        )

        // Element zero is data that is not JSON; element one is not data at all. Each element completes both its
        // storage and proxy conversion before the next element is read.
        assertDecodingError([CodedPayload].persistentKeyValueRepresentation, [malformed, 42], "codable")
        assertDecodingError([CodedPayload?].persistentKeyValueRepresentation, [malformed, 42], "optional")
        assertDecodingError([[CodedPayload]].persistentKeyValueRepresentation, [[malformed, 42]], "nested")
        assertDecodingError([OuterPayload].persistentKeyValueRepresentation, [malformed, 42], "proxy of codable")

        XCTAssertThrowsError(
            try [CodedPayload].persistentKeyValueRepresentation.decode(
                storageObject: [42, malformed],
                format: .propertyList
            )
        ) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
        XCTAssertThrowsError(
            try [ProxiedCount].persistentKeyValueRepresentation.decode(
                storageObject: [-1, "not a number"],
                format: .propertyList
            )
        ) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidValue)
        }
    }

    func test_move_codableArrayWithMalformedElements_reportsFirstElementError() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [CodedPayload]())
        let destination = InMemoryPersistentKeyValueStore()

        userDefaults.set([Data("invalid JSON".utf8), 42] as [Any], forKey: key.id)

        let report = try userDefaults.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.decode)])
        XCTAssertTrue(report.outcomes.first?.error is DecodingError, "\(String(describing: report.outcomes.first?.error))")
        XCTAssertEqual(userDefaults.array(forKey: key.id)?.count, 2)
        XCTAssertNil(destination.object(forKey: key.id))
    }

    func test_move_codableArrayWithUnencodableElement_failsWithCoderErrorAtAnyPosition() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [CodedPayload]())

        for amounts in [[Double.nan, 2], [2, Double.nan]] {
            let source = InMemoryPersistentKeyValueStore()

            source.set(key, to: amounts.map(CodedPayload.init))

            let report = try source.move(key, to: userDefaults, onConflict: .overwriteDestination, tracking: .untracked)

            XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare)], "\(amounts)")
            XCTAssertTrue(report.outcomes.first?.error is EncodingError, "\(amounts)")
            XCTAssertEqual(source.get(key).count, 2, "\(amounts)")
            XCTAssertNil(userDefaults.object(forKey: key.id), "\(amounts)")
        }
    }

    func test_checkedConversion_builtInProxyContainers_throwConversionErrors() {
        let arrays = [ProxiedCount].persistentKeyValueRepresentation
        let dictionaries = [String: ProxiedCount].persistentKeyValueRepresentation

        XCTAssertEqual(try arrays.encode([ProxiedCount(1)], format: .propertyList) as? [Int], [1])
        XCTAssertEqual(try arrays.decode(storageObject: [1], format: .propertyList), [ProxiedCount(1)])
        XCTAssertEqual(
            try dictionaries.encode(["a": ProxiedCount(1)], format: .propertyList) as? [String: Int],
            ["a": 1]
        )
        XCTAssertEqual(try dictionaries.decode(storageObject: ["a": 1], format: .propertyList), ["a": ProxiedCount(1)])

        XCTAssertThrowsError(try arrays.encode([ProxiedCount(1), ProxiedCount(-1)], format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .encodingFailed)
        }
        XCTAssertThrowsError(try arrays.decode(storageObject: [1, -1], format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidValue)
        }
        XCTAssertThrowsError(try dictionaries.encode(["a": ProxiedCount(-1)], format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .encodingFailed)
        }
        XCTAssertThrowsError(try dictionaries.decode(storageObject: ["a": -1], format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidValue)
        }
    }

    func test_checkedEncode_optionalContainers_omitNilValues() throws {
        let arrays = [ProxiedCount?].persistentKeyValueRepresentation
        let dictionaries = [String: ProxiedCount?].persistentKeyValueRepresentation

        XCTAssertEqual(try arrays.encode([nil, ProxiedCount(1), nil], format: .propertyList) as? [Int], [1])
        XCTAssertEqual(try arrays.encode([nil, nil], format: .propertyList) as? [Int], [])
        XCTAssertEqual(
            try dictionaries.encode(["a": ProxiedCount(1), "b": nil], format: .propertyList) as? [String: Int],
            ["a": 1]
        )
        XCTAssertEqual(
            try dictionaries.decode(storageObject: ["a": 1], format: .propertyList),
            ["a": ProxiedCount(1)]
        )
    }
}

// MARK: - Built-In Container Method Tests

// Checked conversion of a built-in representation does not call its container methods, but a custom hook can.
extension CheckedContainerConversionTests {
    func test_set_builtInProxyArray_assignsOrLeavesArray() {
        let representation = ProxiedCount.persistentKeyValueRepresentation
        var array: [Any] = []

        representation.set([ProxiedCount(1), ProxiedCount(-1)], to: &array)

        XCTAssertTrue(array.isEmpty)
        XCTAssertThrowsError(try representation.encode(ProxiedCount(-1), format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .encodingFailed)
        }

        representation.set([ProxiedCount(1), ProxiedCount(2)], to: &array)

        XCTAssertEqual(array as? [Int], [1, 2])
    }

    func test_set_builtInOptionalArray_omitsNilValues() {
        let representation = ProxiedCount?.persistentKeyValueRepresentation
        var array: [Any] = []

        representation.set([nil, ProxiedCount(1), nil], to: &array)

        XCTAssertEqual(array as? [Int], [1])
    }

    func test_set_nestedContainersInUserDefaults_omitNilValuesOrLeaveStoredValue() {
        let arrays = PersistentKey("key:\(#function).arrays", defaultValue: [[ProxiedCount?]]())
        let dictionaries = PersistentKey("key:\(#function).dictionaries", defaultValue: [String: [ProxiedCount?]]())

        // Every value of an inner container encodes to `nil`, which omits it rather than failing the write.
        userDefaults.set(arrays, to: [[nil, nil], [ProxiedCount(1)]])
        userDefaults.set(dictionaries, to: ["a": [nil], "b": [ProxiedCount(2)]])

        XCTAssertEqual(userDefaults.array(forKey: arrays.id) as? [[Int]], [[], [1]])
        XCTAssertEqual(userDefaults.dictionary(forKey: dictionaries.id) as? [String: [Int]], ["a": [], "b": [2]])

        // A value that fails to encode leaves the stored value unchanged.
        userDefaults.set(arrays, to: [[nil], [ProxiedCount(-1)]])
        userDefaults.set(dictionaries, to: ["a": [nil], "b": [ProxiedCount(-1)]])

        XCTAssertEqual(userDefaults.array(forKey: arrays.id) as? [[Int]], [[], [1]])
        XCTAssertEqual(userDefaults.dictionary(forKey: dictionaries.id) as? [String: [Int]], ["a": [], "b": [2]])
    }

    func test_set_builtInNestedContainers_assignsOrLeavesArray() {
        var arrays: [Any] = []
        var dictionaries: [Any] = []

        [ProxiedCount].set([[ProxiedCount(1)], [ProxiedCount(-1)]], to: &arrays)
        [String: ProxiedCount].set([["a": ProxiedCount(1)], ["b": ProxiedCount(-1)]], to: &dictionaries)

        XCTAssertTrue(arrays.isEmpty)
        XCTAssertTrue(dictionaries.isEmpty)

        [ProxiedCount].set([[ProxiedCount(1)], [ProxiedCount(2)]], to: &arrays)
        [String: ProxiedCount].set([["a": ProxiedCount(1)], ["b": ProxiedCount(2)]], to: &dictionaries)

        XCTAssertEqual(arrays as? [[Int]], [[1], [2]])
        XCTAssertEqual(dictionaries as? [[String: Int]], [["a": 1], ["b": 2]])
    }
}

// MARK: - Private Instance Interface

extension CheckedContainerConversionTests {
    private func assertDecodingError<Representation: PersistentKeyValueRepresentation>(
        _ representation: Representation,
        _ object: Any,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try representation.decode(storageObject: object, format: .propertyList),
            message,
            file: file,
            line: line
        ) {
            XCTAssertTrue($0 is DecodingError, "\(message): \($0)", file: file, line: line)
        }
    }

    private func assertEncodingError<Representation: PersistentKeyValueRepresentation>(
        _ representation: Representation,
        _ value: Representation.Value,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try representation.encode(value, format: .propertyList),
            message,
            file: file,
            line: line
        ) {
            XCTAssertTrue($0 is EncodingError, "\(message): \($0)", file: file, line: line)
        }
    }

    /// Runs `body` on the calling thread or on a newly detached thread, waiting for it to finish.
    private func perform<Result>(
        onWorkerThread: Bool,
        _ body: @escaping @Sendable () throws -> Result
    ) throws -> Result {
        guard onWorkerThread else {
            return try body()
        }

        let outcome = WorkerThreadOutcome<Result>()

        Thread.detachNewThread {
            outcome.finish(Swift.Result(catching: body))
        }

        return try outcome.wait().get()
    }
}

// MARK: - Worker Thread Outcome Definition

/// The result of work run on a detached thread.
private final class WorkerThreadOutcome<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<Value, any Error>?

    // MARK: Internal Instance Interface

    func finish(_ result: Result<Value, any Error>) {
        lock.withLock {
            self.result = result
        }

        semaphore.signal()
    }

    func wait() -> Result<Value, any Error> {
        semaphore.wait()

        return lock.withLock {
            result!
        }
    }
}

// MARK: - Hook Row Definitions

/// A row of counts whose representation decodes arrays with a custom hook.
private protocol HookRow: Equatable, KeyValuePersistible, Sendable {
    var counts: [String: Int] { get }

    init(counts: [String: Int])
}

/// A row whose array hook decodes on the calling thread.
private struct InlineHookRow: HookRow {
    let counts: [String: Int]

    static var persistentKeyValueRepresentation: HookRowRepresentation<Self> {
        HookRowRepresentation(decodesOnWorkerThread: false)
    }
}

/// A row whose array hook hands decoding to a worker thread and waits for it.
private struct WorkerThreadHookRow: HookRow {
    let counts: [String: Int]

    static var persistentKeyValueRepresentation: HookRowRepresentation<Self> {
        HookRowRepresentation(decodesOnWorkerThread: true)
    }
}

/// A representation whose array hook decodes rows with the ordinary `[String: Int]` array read.
private struct HookRowRepresentation<Row: HookRow>: ProxyPersistentKeyValueRepresentationProtocol {
    let decodesOnWorkerThread: Bool

    // MARK: ProxyPersistentKeyValueRepresentationProtocol Implementation

    func from(_ proxy: [String: Int]) -> Row? {
        Row(counts: proxy)
    }

    func to(_ value: Row) -> [String: Int]? {
        value.counts
    }

    // MARK: Interfacing with Property List Array

    func get(from propertyListArray: [Any]) -> [Row]? {
        guard decodesOnWorkerThread else {
            return Self.rows(from: propertyListArray)
        }

        let input = UncheckedSendableBox(propertyListArray)
        let outcome = WorkerThreadOutcome<UncheckedSendableBox<[Row]?>>()

        Thread.detachNewThread {
            outcome.finish(.success(UncheckedSendableBox(Self.rows(from: input.value))))
        }

        switch outcome.wait() {
        case let .success(rows):
            return rows.value
        case .failure:
            return nil
        }
    }

    // MARK: Private Static Interface

    private static func rows(from propertyListArray: [Any]) -> [Row]? {
        [String: Int].persistentKeyValueRepresentation.get(from: propertyListArray)?.map(Row.init(counts:))
    }
}

/// Carries a non-`Sendable` value to a thread that the sender waits for.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

// MARK: - Settings Reading Value Definition

/// A value whose decoding performs an ordinary read of a settings key, both synchronously and in a `Task`.
private struct SettingsReadingValue: Equatable, KeyValuePersistible, Sendable {
    let number: Int

    static var persistentKeyValueRepresentation: Representation {
        Representation()
    }

    struct Representation: PersistentKeyValueKit.PersistentKeyValueRepresentation {
        func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> SettingsReadingValue {
            guard let number = storageObject as? Int else {
                throw PersistentKeyValueConversionError.invalidStorageValue
            }

            SettingsReadRecorder.current?.recordReads()

            return SettingsReadingValue(number: number)
        }

        func encode(_ value: SettingsReadingValue, format: PersistentKeyValueStorageFormat) throws -> Any? {
            value.number
        }
    }
}

/// Records ordinary reads of a settings key made while a value decodes.
private final class SettingsReadRecorder: @unchecked Sendable {
    @TaskLocal static var current: SettingsReadRecorder?

    private let key: PersistentKey<[[String: Int]]>
    private let lock = NSLock()
    private let taskRead = DispatchSemaphore(value: 0)
    private let userDefaults: UserDefaults
    private var reads: [[[String: Int]]] = []
    private var taskReads: [[[String: Int]]] = []

    // MARK: Internal Initialization

    init(userDefaults: UserDefaults, key: PersistentKey<[[String: Int]]>) {
        self.userDefaults = userDefaults
        self.key = key
    }

    // MARK: Internal Instance Interface

    var synchronousReads: [[[String: Int]]] {
        lock.withLock {
            reads
        }
    }

    func recordReads() {
        let read = userDefaults.get(key)

        lock.withLock {
            reads.append(read)
        }

        Task {
            let read = userDefaults.get(key)

            lock.withLock {
                taskReads.append(read)
            }

            taskRead.signal()
        }
    }

    func waitForTaskRead() -> [[String: Int]]? {
        taskRead.wait()

        return lock.withLock {
            taskReads.first
        }
    }
}

// MARK: - Recursive Node Definitions

/// Counts conversions performed by a recursive codec.
private final class ConversionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var decodeCount = 0
    private var encodeCount = 0

    // MARK: Internal Instance Interface

    var decodes: Int {
        lock.withLock {
            decodeCount
        }
    }

    var encodes: Int {
        lock.withLock {
            encodeCount
        }
    }

    func countDecode() {
        lock.withLock {
            decodeCount += 1
        }
    }

    func countEncode() {
        lock.withLock {
            encodeCount += 1
        }
    }

    func reset() {
        lock.withLock {
            decodeCount = 0
            encodeCount = 0
        }
    }
}

/// A tree whose codec delegates its children to `[RecursiveListNode]`.
private indirect enum RecursiveListNode: Equatable, KeyValuePersistible {
    case branch([RecursiveListNode])
    case invalid

    static var persistentKeyValueRepresentation: Representation {
        Representation()
    }

    struct Representation: PersistentKeyValueKit.PersistentKeyValueRepresentation {
        static let counter = ConversionCounter()

        func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> RecursiveListNode {
            Self.counter.countDecode()

            guard storageObject is [Any] else {
                throw PersistentKeyValueConversionError.invalidStorageValue
            }

            return .branch(try [RecursiveListNode].decode(storageObject: storageObject, format: format))
        }

        func encode(_ value: RecursiveListNode, format: PersistentKeyValueStorageFormat) throws -> Any? {
            Self.counter.countEncode()

            switch value {
            case let .branch(children):
                return try children.encode(format: format)
            case .invalid:
                throw PersistentKeyValueConversionError.invalidValue
            }
        }
    }
}

/// A tree whose codec delegates its children to `[String: RecursiveMapNode]`.
private indirect enum RecursiveMapNode: KeyValuePersistible {
    case branch([String: RecursiveMapNode])
    case invalid

    static var persistentKeyValueRepresentation: Representation {
        Representation()
    }

    struct Representation: PersistentKeyValueKit.PersistentKeyValueRepresentation {
        static let counter = ConversionCounter()

        func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> RecursiveMapNode {
            Self.counter.countDecode()

            guard storageObject is [String: Any] else {
                throw PersistentKeyValueConversionError.invalidStorageValue
            }

            return .branch(try [String: RecursiveMapNode].decode(storageObject: storageObject, format: format))
        }

        func encode(_ value: RecursiveMapNode, format: PersistentKeyValueStorageFormat) throws -> Any? {
            Self.counter.countEncode()

            switch value {
            case let .branch(children):
                return try children.encode(format: format)
            case .invalid:
                throw PersistentKeyValueConversionError.invalidValue
            }
        }
    }
}

// MARK: - Coded Payload Definition

/// A value persisted as JSON data, which cannot encode a `nan` amount.
private struct CodedPayload: Codable, Equatable, KeyValuePersistible {
    let amount: Double

    typealias Representation = CodablePersistentKeyValueRepresentation<Self, JSONEncoder, JSONDecoder>

    static var persistentKeyValueRepresentation: Representation {
        Representation(encoder: JSONEncoder(), decoder: JSONDecoder())
    }
}

// MARK: - Outer Payload Definition

/// A value persisted through a closure proxy whose proxy is a ``CodedPayload``.
private struct OuterPayload: Equatable, KeyValuePersistible {
    let payload: CodedPayload

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, CodedPayload> {
        ProxyPersistentKeyValueRepresentation(
            to: { $0.payload },
            from: { OuterPayload(payload: $0) }
        )
    }
}

// MARK: - Proxied Count Definition

/// A count persisted through a closure proxy that rejects negative numbers in both directions.
private struct ProxiedCount: Equatable, KeyValuePersistible {
    let number: Int

    init(_ number: Int) {
        self.number = number
    }

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, Int> {
        ProxyPersistentKeyValueRepresentation(
            to: { $0.number < 0 ? nil : $0.number },
            from: { $0 < 0 ? nil : ProxiedCount($0) }
        )
    }
}
