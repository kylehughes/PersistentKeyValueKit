//
//  PersistentValueTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/5/24.
//

#if !os(watchOS)

import Combine
import PersistentKeyValueKit
import SwiftUI
import XCTest

#if os(macOS)
private typealias ViewController = NSViewController
#elseif canImport(UIKit)
private typealias ViewController = UIViewController
#endif

final class PersistentValueTests: XCTestCase {
    let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
    var userDefaults: UserDefaults!
    var suiteName: String!
    
    var cancellables = Set<AnyCancellable>()
    
    // MARK: XCTestCase Implementation

    override public func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentValueTests", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override public func tearDown() {
        cancellables.removeAll()
        ubiquitousKeyValueStore.dictionaryRepresentation.keys.forEach(ubiquitousKeyValueStore.removeObject)
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        userDefaults = nil
        suiteName = nil
    }
    
    // MARK: Private Instance Interface
    
    #if os(macOS)
    @MainActor
    private final func host<V: View>(_ view: V, in viewController: NSViewController) {
        let hosting = NSHostingController(rootView: view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        
        viewController.addChild(hosting)
        viewController.view.addSubview(hosting.view)
        
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            hosting.view.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
        ])
        
        viewController.view.layoutSubtreeIfNeeded()
    }
    #elseif canImport(UIKit)
    @MainActor
    private final func host<V: View>(_ view: V, in viewController: UIViewController) {
        let hosting = UIHostingController(rootView: view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        
        viewController.addChild(hosting)
        viewController.view.addSubview(hosting.view)
        
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            hosting.view.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
        ])
        
        viewController.view.layoutIfNeeded()
    }
    #endif
}

// MARK: - Projected Value Tests

extension PersistentValueTests {
    // MARK: Tests
    
    @MainActor
    func test_projectedValue_userDefaults() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let boundValue = "boundValue: \(#function)"
        let externalValue = "externalValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: userDefaults)
        
        let defaultValueExpectation = expectation(
            description: "Initial value is \(defaultValue)"
        )
        let boundValueExpectation = expectation(
            description: "Value updated to \(boundValue) via binding"
        )
        let externalValueExpectation = expectation(
            description: "Value updated to \(externalValue) externally"
        )
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case boundValue:
                boundValueExpectation.fulfill()
            case externalValue:
                externalValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)
        
        host(view, in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)

        view.binding.send(boundValue)

        await fulfillment(of: [boundValueExpectation], timeout: 10)

        userDefaults.set(externalValue, forKey: keyID)
        
        await fulfillment(of: [externalValueExpectation], timeout: 10)
    }
    
    @MainActor
    func test_projectedValue_ubiquitousKeyValueStore() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let boundValue = "boundValue: \(#function)"
        let externalValue = "externalValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: ubiquitousKeyValueStore)
        
        let defaultValueExpectation = expectation(
            description: "Initial value is \(defaultValue)"
        )
        let boundValueExpectation = expectation(
            description: "Value updated to \(boundValue) via binding"
        )
        let externalValueExpectation = expectation(
            description: "Value updated to \(externalValue) externally"
        )
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case boundValue:
                boundValueExpectation.fulfill()
            case externalValue:
                externalValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)
        
        host(view, in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)

        view.binding.send(boundValue)

        await fulfillment(of: [boundValueExpectation], timeout: 10)

        ubiquitousKeyValueStore.set(externalValue, forKey: keyID)
        
        await fulfillment(of: [externalValueExpectation], timeout: 10)
    }
    
    @MainActor
    func test_projectedValue_defaultStore() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let boundValue = "boundValue: \(#function)"
        let externalValue = "externalValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: nil)
        
        let defaultValueExpectation = expectation(
            description: "Initial value is \(defaultValue)"
        )
        let boundValueExpectation = expectation(
            description: "Value updated to \(boundValue) via binding"
        )
        let externalValueExpectation = expectation(
            description: "Value updated to \(externalValue) externally"
        )
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case boundValue:
                boundValueExpectation.fulfill()
            case externalValue:
                externalValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)
        
        host(view.defaultPersistentKeyValueStore(userDefaults), in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)

        view.binding.send(boundValue)

        await fulfillment(of: [boundValueExpectation], timeout: 10)

        userDefaults.set(externalValue, forKey: keyID)
        
        await fulfillment(of: [externalValueExpectation], timeout: 10)
    }
}

// MARK: - End-to-End Tests

extension PersistentValueTests {
    // MARK: Tests
    
    @MainActor
    func test_explicit_userDefaults() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let externalStoredValue = "exteranlStoredValue: \(#function)"
        let internalStoredValue = "internalStoredValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: userDefaults)

        let defaultValueExpectation = expectation(
            description: "PersistentValue starts as \(defaultValue)"
        )
        let externalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(externalStoredValue)"
        )
        let internalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(internalStoredValue)"
        )
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case externalStoredValue:
                externalStoredValueExpectation.fulfill()
            case internalStoredValue:
                internalStoredValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)

        host(view, in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)

        userDefaults.set(externalStoredValue, forKey: keyID)

        await fulfillment(of: [externalStoredValueExpectation], timeout: 10)

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation], timeout: 10)
    }
    
    @MainActor
    func test_explicit_userDefaults_ignoreDefaultViewModifier() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let ubiquitousStoredValue = "ubiquitousStoredValue: \(#function)"
        let userDefaultsStoredValue = "userDefaultsStoredValue: \(#function)"
        let internalStoredValue = "internalStoredValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        let view = TestView(key: key, store: userDefaults)

        let defaultValueExpectation = expectation(
            description: "PersistentValue starts as \(defaultValue)"
        )
        let correctValueExpectation = expectation(
            description: "PersistentValue updates to \(userDefaultsStoredValue)"
        )
        let internalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(internalStoredValue)"
        )
        let incorrectValueExpectation = expectation(
            description: "PersistentValue does not update to \(ubiquitousStoredValue)"
        )
        incorrectValueExpectation.isInverted = true
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case ubiquitousStoredValue:
                incorrectValueExpectation.fulfill()
            case userDefaultsStoredValue:
                correctValueExpectation.fulfill()
            case internalStoredValue:
                internalStoredValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)

        host(view.defaultPersistentKeyValueStore(ubiquitousKeyValueStore), in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)
        
        userDefaults.set(userDefaultsStoredValue, forKey: keyID)

        await fulfillment(of: [correctValueExpectation], timeout: 10)
        
        ubiquitousKeyValueStore.set(ubiquitousStoredValue, forKey: keyID)
        
        await fulfillment(of: [incorrectValueExpectation], timeout: 1)

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation], timeout: 10)
    }

    @MainActor
    func test_explicit_userDefaults_observesKeyPathIncompatibleKeys() async {
        for keyID in keyPathIncompatibleKeyIDs() {
            let viewController = ViewController()
            let key = PersistentKey(keyID, defaultValue: 0)
            let model = SwitchingModel(keyID: keyID, store: userDefaults, environmentStore: userDefaults)
            let recorder = SwitchingRecorder()

            host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
            await waitForRenderedValue(0, in: recorder)

            userDefaults.set(key, to: 1)
            await waitForRenderedValue(1, in: recorder)

            userDefaults.remove(key)
            await waitForRenderedValue(0, in: recorder)
        }
    }

    @MainActor
    func test_explicit_ubiquitousKeyValueStore() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let externalStoredValue = "externalStoredValue: \(#function)"
        let internalStoredValue = "internalStoredValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: ubiquitousKeyValueStore)
        
        let defaultValueExpectation = expectation(
            description: "PersistentValue starts as \(defaultValue)"
        )
        let externalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(externalStoredValue)"
        )
        let internalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(internalStoredValue)"
        )
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case externalStoredValue:
                externalStoredValueExpectation.fulfill()
            case internalStoredValue:
                internalStoredValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)

        host(view, in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)

        ubiquitousKeyValueStore.set(externalStoredValue, forKey: keyID)

        await fulfillment(of: [externalStoredValueExpectation], timeout: 10)

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation], timeout: 10)
    }
    
    @MainActor
    func test_explicit_ubiquitousKeyValueStore_ignoreDefaultViewModifier() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let ubiquitousStoredValue = "ubiquitousStoredValue: \(#function)"
        let userDefaultsStoredValue = "userDefaultsStoredValue: \(#function)"
        let internalStoredValue = "internalStoredValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: ubiquitousKeyValueStore)

        let defaultValueExpectation = expectation(
            description: "PersistentValue starts as \(defaultValue)"
        )
        let correctValueExpectation = expectation(
            description: "PersistentValue updates to \(ubiquitousStoredValue)"
        )
        let internalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(internalStoredValue)"
        )
        let incorrectValueExpectation = expectation(
            description: "PersistentValue does not update to \(userDefaultsStoredValue)"
        )
        incorrectValueExpectation.isInverted = true
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case ubiquitousStoredValue:
                correctValueExpectation.fulfill()
            case userDefaultsStoredValue:
                incorrectValueExpectation.fulfill()
            case internalStoredValue:
                internalStoredValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)

        host(view.defaultPersistentKeyValueStore(userDefaults), in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)

        ubiquitousKeyValueStore.set(ubiquitousStoredValue, forKey: keyID)

        await fulfillment(of: [correctValueExpectation], timeout: 10)
        
        userDefaults.set(userDefaultsStoredValue, forKey: keyID)
        
        await fulfillment(of: [incorrectValueExpectation], timeout: 1)

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation], timeout: 10)
    }
    
    @MainActor
    func test_explicit_nil_defaultViewModifier_default() async {
        // `store: nil` with no default-store modifier resolves to the app domain, so this test must use it. Remove only
        // the key it writes; the domain is shared with other test processes.
        let userDefaults = UserDefaults.standard
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        defer { userDefaults.removeObject(forKey: keyID) }
        let externalStoredValue = "externalStoredValue: \(#function)"
        let internalStoredValue = "internalStoredValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: nil)
        
        let defaultValueExpectation = expectation(
            description: "PersistentValue starts as \(defaultValue)"
        )
        let externalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(externalStoredValue)"
        )
        let internalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(internalStoredValue)"
        )
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case externalStoredValue:
                externalStoredValueExpectation.fulfill()
            case internalStoredValue:
                internalStoredValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)

        host(view, in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)
        
        userDefaults.set(externalStoredValue, forKey: keyID)

        await fulfillment(of: [externalStoredValueExpectation], timeout: 10)

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation], timeout: 10)
    }
    
    @MainActor
    func test_explicit_nil_defaultViewModifier_userDefaults() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let externalStoredValue = "externalStoredValue: \(#function)"
        let internalStoredValue = "internalStoredValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: nil)

        let defaultValueExpectation = expectation(
            description: "PersistentValue starts as \(defaultValue)"
        )
        let externalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(externalStoredValue)"
        )
        let internalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(internalStoredValue)"
        )
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case externalStoredValue:
                externalStoredValueExpectation.fulfill()
            case internalStoredValue:
                internalStoredValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)

        host(view.defaultPersistentKeyValueStore(userDefaults), in: viewController)
        
        await fulfillment(of: [defaultValueExpectation], timeout: 10)
        
        userDefaults.set(externalStoredValue, forKey: keyID)
        
        await fulfillment(of: [externalStoredValueExpectation], timeout: 10)

        view.input.send(internalStoredValue)
        
        await fulfillment(of: [internalStoredValueExpectation], timeout: 10)
    }
    
    @MainActor
    func test_explicit_nil_defaultViewModifier_ubiquitousKeyValueStore() async {
        let viewController = ViewController()
        let defaultValue = "defaultValue"
        let keyID = "key:\(#function)"
        let externalStoredValue = "externalStoredValue: \(#function)"
        let internalStoredValue = "internalStoredValue: \(#function)"
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        let view = TestView(key: key, store: nil)

        let defaultValueExpectation = expectation(
            description: "PersistentValue starts as \(defaultValue)"
        )
        let externalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(externalStoredValue)"
        )
        let internalStoredValueExpectation = expectation(
            description: "PersistentValue updates to \(internalStoredValue)"
        )
        
        view.output.sink { value in
            switch value {
            case defaultValue:
                defaultValueExpectation.fulfill()
            case externalStoredValue:
                externalStoredValueExpectation.fulfill()
            case internalStoredValue:
                internalStoredValueExpectation.fulfill()
            default:
                break
            }
        }.store(in: &cancellables)

        host(view.defaultPersistentKeyValueStore(ubiquitousKeyValueStore), in: viewController)

        await fulfillment(of: [defaultValueExpectation], timeout: 10)

        ubiquitousKeyValueStore.set(externalStoredValue, forKey: keyID)

        await fulfillment(of: [externalStoredValueExpectation], timeout: 10)

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation], timeout: 10)
    }
}

// MARK: - Input Change Tests

extension PersistentValueTests {
    // MARK: Tests

    @MainActor
    func test_inputChange_environmentStore_bindingWritesNewStore() async {
        let viewController = ViewController()
        let firstStore = InMemoryPersistentKeyValueStore()
        let secondStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let model = SwitchingModel(keyID: key.id, environmentStore: firstStore)
        let recorder = SwitchingRecorder()

        firstStore.set(key, to: 1)
        secondStore.set(key, to: 2)

        host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
        await waitForRenderedValue(1, in: recorder)

        model.environmentStore = secondStore
        await waitForRenderedValue(2, in: recorder)

        recorder.binding?.wrappedValue = 7

        XCTAssertEqual(firstStore.get(key), 1)
        XCTAssertEqual(secondStore.get(key), 7)

        secondStore.set(key, to: 9)
        await waitForRenderedValue(9, in: recorder)
    }

    @MainActor
    func test_inputChange_explicitStore_bindingWritesNewStore() async {
        let viewController = ViewController()
        let firstStore = InMemoryPersistentKeyValueStore()
        let secondStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let model = SwitchingModel(keyID: key.id, store: firstStore, environmentStore: userDefaults)
        let recorder = SwitchingRecorder()

        firstStore.set(key, to: 1)
        secondStore.set(key, to: 2)

        host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
        await waitForRenderedValue(1, in: recorder)

        model.store = secondStore
        await waitForRenderedValue(2, in: recorder)

        recorder.binding?.wrappedValue = 7

        XCTAssertEqual(firstStore.get(key), 1)
        XCTAssertEqual(secondStore.get(key), 7)

        secondStore.set(key, to: 9)
        await waitForRenderedValue(9, in: recorder)
    }

    @MainActor
    func test_inputChange_explicitValueTypeStore_observesChanges() async {
        let viewController = ViewController()
        let baseStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let model = SwitchingModel(keyID: key.id, store: ForwardingStore(base: baseStore), environmentStore: userDefaults)
        let recorder = SwitchingRecorder()

        baseStore.set(key, to: 1)

        host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
        await waitForRenderedValue(1, in: recorder)

        baseStore.set(key, to: 2)
        await waitForRenderedValue(2, in: recorder)

        recorder.binding?.wrappedValue = 7

        XCTAssertEqual(baseStore.get(key), 7)

        baseStore.set(key, to: 9)
        await waitForRenderedValue(9, in: recorder)
    }

    @MainActor
    func test_inputChange_key_bindingWritesNewKey() async {
        let viewController = ViewController()
        let store = InMemoryPersistentKeyValueStore()
        let firstKey = PersistentKey("firstKey:\(#function)", defaultValue: 0)
        let secondKey = PersistentKey("secondKey:\(#function)", defaultValue: 0)
        let model = SwitchingModel(keyID: firstKey.id, store: store, environmentStore: userDefaults)
        let recorder = SwitchingRecorder()

        store.set(firstKey, to: 1)
        store.set(secondKey, to: 2)

        host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
        await waitForRenderedValue(1, in: recorder)

        model.keyID = secondKey.id
        await waitForRenderedValue(2, in: recorder)

        recorder.binding?.wrappedValue = 7

        XCTAssertEqual(store.get(firstKey), 1)
        XCTAssertEqual(store.get(secondKey), 7)

        store.set(secondKey, to: 9)
        await waitForRenderedValue(9, in: recorder)
    }

    @MainActor
    func test_inputChange_canonicallyEquivalentKey_observesNewKey() async {
        let viewController = ViewController()
        let composedKey = PersistentKey("caf\u{E9}:\(#function)", defaultValue: 0)
        let decomposedKey = PersistentKey("cafe\u{301}:\(#function)", defaultValue: 0)
        let model = SwitchingModel(keyID: composedKey.id, store: userDefaults, environmentStore: userDefaults)
        let recorder = SwitchingRecorder()

        userDefaults.set(composedKey, to: 1)
        userDefaults.set(decomposedKey, to: 2)

        host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
        await waitForRenderedValue(1, in: recorder)

        model.keyID = decomposedKey.id
        await waitForRenderedValue(2, in: recorder)

        userDefaults.set(decomposedKey, to: 42)
        await waitForRenderedValue(42, in: recorder)

        XCTAssertEqual(userDefaults.get(composedKey), 1)
    }

    @MainActor
    func test_inputChange_environmentStore_retainedBindingWritesOriginalStore() async {
        let viewController = ViewController()
        let firstStore = InMemoryPersistentKeyValueStore()
        let secondStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let model = SwitchingModel(keyID: key.id, environmentStore: firstStore)
        let recorder = SwitchingRecorder()

        firstStore.set(key, to: 1)
        secondStore.set(key, to: 2)

        host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
        await waitForRenderedValue(1, in: recorder)

        let retainedBinding = recorder.binding

        model.environmentStore = secondStore
        await waitForRenderedValue(2, in: recorder)

        retainedBinding?.wrappedValue = 73

        XCTAssertEqual(retainedBinding?.wrappedValue, 73)
        XCTAssertEqual(firstStore.get(key), 73)
        XCTAssertEqual(secondStore.get(key), 2)
    }

    @MainActor
    func test_inputChange_explicitStore_retainedBindingWritesOriginalStore() async {
        let viewController = ViewController()
        let firstStore = InMemoryPersistentKeyValueStore()
        let secondStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let model = SwitchingModel(keyID: key.id, store: firstStore, environmentStore: userDefaults)
        let recorder = SwitchingRecorder()

        firstStore.set(key, to: 1)
        secondStore.set(key, to: 2)

        host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
        await waitForRenderedValue(1, in: recorder)

        let retainedBinding = recorder.binding

        model.store = secondStore
        await waitForRenderedValue(2, in: recorder)

        retainedBinding?.wrappedValue = 93

        XCTAssertEqual(retainedBinding?.wrappedValue, 93)
        XCTAssertEqual(firstStore.get(key), 93)
        XCTAssertEqual(secondStore.get(key), 2)
    }

    @MainActor
    func test_inputChange_key_retainedBindingWritesOriginalKey() async {
        let viewController = ViewController()
        let store = InMemoryPersistentKeyValueStore()
        let firstKey = PersistentKey("firstKey:\(#function)", defaultValue: 0)
        let secondKey = PersistentKey("secondKey:\(#function)", defaultValue: 0)
        let model = SwitchingModel(keyID: firstKey.id, store: store, environmentStore: userDefaults)
        let recorder = SwitchingRecorder()

        store.set(firstKey, to: 1)
        store.set(secondKey, to: 2)

        host(SwitchingRoot(model: model, recorder: recorder), in: viewController)
        await waitForRenderedValue(1, in: recorder)

        let retainedBinding = recorder.binding

        model.keyID = secondKey.id
        await waitForRenderedValue(2, in: recorder)

        retainedBinding?.wrappedValue = 73

        XCTAssertEqual(retainedBinding?.wrappedValue, 73)
        XCTAssertEqual(store.get(firstKey), 73)
        XCTAssertEqual(store.get(secondKey), 2)
    }

    @MainActor
    func test_inputChange_retainedBindingDoesNotRetainLaterStore() async {
        let firstStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let recorder = SwitchingRecorder()
        var retainedBinding: Binding<Int>?
        var viewController: ViewController? = ViewController()
        weak var releasedSecondStore: InMemoryPersistentKeyValueStore?

        do {
            let secondStore = InMemoryPersistentKeyValueStore()
            let model = SwitchingModel(keyID: key.id, store: firstStore, environmentStore: userDefaults)

            releasedSecondStore = secondStore
            firstStore.set(key, to: 1)
            secondStore.set(key, to: 2)

            host(SwitchingRoot(model: model, recorder: recorder), in: viewController!)
            await waitForRenderedValue(1, in: recorder)

            retainedBinding = recorder.binding

            model.store = secondStore
            await waitForRenderedValue(2, in: recorder)
        }

        // Release the view, keeping only the binding for the first store.
        recorder.binding = nil
        viewController = nil

        await waitForRelease { releasedSecondStore == nil }

        XCTAssertNil(releasedSecondStore)
        XCTAssertEqual(retainedBinding?.wrappedValue, 1)

        retainedBinding?.wrappedValue = 3

        XCTAssertEqual(firstStore.get(key), 3)
    }

    // MARK: Private Instance Interface

    /// Waits until `isReleased` returns `true`, giving up after a bounded timeout.
    @MainActor
    private func waitForRelease(_ isReleased: () -> Bool) async {
        let deadline = Date(timeIntervalSinceNow: 5)

        while !isReleased(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Waits until the row renders `value`, failing after a bounded timeout.
    @MainActor
    private func waitForRenderedValue(_ value: Int, in recorder: SwitchingRecorder) async {
        guard recorder.renderedValue != value else {
            return
        }

        let rendered = expectation(description: "Rendered \(value)")

        recorder.onRender = { renderedValue in
            guard renderedValue == value else {
                return
            }

            recorder.onRender = nil
            rendered.fulfill()
        }

        await fulfillment(of: [rendered], timeout: 5)
        recorder.onRender = nil
    }
}

// MARK: - ForwardingStore Definition

/// A value-type store that forwards every operation to a backing store.
private struct ForwardingStore: PersistentKeyValueStore {
    let base: InMemoryPersistentKeyValueStore

    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        base.migrationEndpoint
    }

    func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        base.deregister(observer, for: key, context: context)
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        base.get(key)
    }

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        base.register(observer: observer, for: key, with: context, and: selector)
    }

    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        base.remove(key)
    }

    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        base.set(key, to: value)
    }
}

// MARK: - SwitchingModel Definition

/// The inputs a parent view passes to a row whose identity stays the same.
@MainActor
private final class SwitchingModel: ObservableObject {
    @Published var environmentStore: any PersistentKeyValueStore
    @Published var keyID: String
    @Published var store: (any PersistentKeyValueStore)?

    init(
        keyID: String,
        store: (any PersistentKeyValueStore)? = nil,
        environmentStore: any PersistentKeyValueStore
    ) {
        self.environmentStore = environmentStore
        self.keyID = keyID
        self.store = store
    }
}

// MARK: - SwitchingRecorder Definition

/// Records the value and binding from the row's most recent render.
@MainActor
private final class SwitchingRecorder {
    var binding: Binding<Int>?
    var onRender: ((Int) -> Void)?
    var renderedValue: Int?

    func record(_ value: Int, binding: Binding<Int>) {
        renderedValue = value
        self.binding = binding
        onRender?(value)
    }
}

// MARK: - SwitchingRoot Definition

private struct SwitchingRoot: View {
    @ObservedObject var model: SwitchingModel

    let recorder: SwitchingRecorder

    var body: some View {
        SwitchingRow(keyID: model.keyID, store: model.store, recorder: recorder)
            .defaultPersistentKeyValueStore(model.environmentStore)
    }
}

// MARK: - SwitchingRow Definition

private struct SwitchingRow: View {
    @PersistentValue<PersistentKey<Int>> var value: Int

    let recorder: SwitchingRecorder

    init(keyID: String, store: (any PersistentKeyValueStore)?, recorder: SwitchingRecorder) {
        _value = PersistentValue(PersistentKey(keyID, defaultValue: 0), store: store)
        self.recorder = recorder
    }

    var body: some View {
        recorder.record(value, binding: $value)

        return Text(String(value))
    }
}

// MARK: - TestView Definition

private struct TestView {
    @PersistentValue<PersistentKey> var persistentValue: String
    
    let binding = PassthroughSubject<String, Never>()
    let input = PassthroughSubject<String, Never>()
    let output = PassthroughSubject<String, Never>()
    
    // MARK: Internal Initialization
    
    @MainActor
    internal init(key: PersistentKey<String>, store: (any PersistentKeyValueStore)?) {
        _persistentValue = PersistentValue(key, store: store)
    }
}

// MARK: - View Extension

extension TestView: View {
    // MARK: View Body
    
    internal var body: some View {
        Text("Test View")
            .onAppear {
                output.send(persistentValue)
            }
            .onPersistentValueChange(of: persistentValue) { newValue in
                output.send(newValue)
            }
            .onReceive(input) { newValue in
                persistentValue = newValue
            }
            .onReceive(binding) { newValue in
                $persistentValue.wrappedValue = newValue
            }
    }
}

// MARK: - View Compatibility Extension

extension View {
    // MARK: Fileprivate Instance Interface
    
    @ViewBuilder
    fileprivate func onPersistentValueChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

#endif
