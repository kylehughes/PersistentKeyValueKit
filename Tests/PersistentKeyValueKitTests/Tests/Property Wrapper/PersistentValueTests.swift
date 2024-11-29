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
    let userDefaults = UserDefaults.standard
    
    var cancellables = Set<AnyCancellable>()
    
    // MARK: XCTestCase Implementation

    override public func tearDown() {
        cancellables.removeAll()
        ubiquitousKeyValueStore.dictionaryRepresentation.keys.forEach(ubiquitousKeyValueStore.removeObject)
        userDefaults.dictionaryRepresentation().keys.forEach(userDefaults.removeObject)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
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

        await fulfillment(of: [defaultValueExpectation])

        view.binding.send(boundValue)

        await fulfillment(of: [boundValueExpectation])

        userDefaults.set(externalValue, forKey: keyID)
        
        await fulfillment(of: [externalValueExpectation])
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

        await fulfillment(of: [defaultValueExpectation])

        view.binding.send(boundValue)

        await fulfillment(of: [boundValueExpectation])

        ubiquitousKeyValueStore.set(externalValue, forKey: keyID)
        
        await fulfillment(of: [externalValueExpectation])
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

        await fulfillment(of: [defaultValueExpectation])

        view.binding.send(boundValue)

        await fulfillment(of: [boundValueExpectation])

        userDefaults.set(externalValue, forKey: keyID)
        
        await fulfillment(of: [externalValueExpectation])
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

        await fulfillment(of: [defaultValueExpectation])

        userDefaults.set(externalStoredValue, forKey: keyID)

        await fulfillment(of: [externalStoredValueExpectation])

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation])
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

        await fulfillment(of: [defaultValueExpectation])
        
        userDefaults.set(userDefaultsStoredValue, forKey: keyID)

        await fulfillment(of: [correctValueExpectation])
        
        ubiquitousKeyValueStore.set(ubiquitousStoredValue, forKey: keyID)
        
        await fulfillment(of: [incorrectValueExpectation], timeout: 1)

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation])
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

        await fulfillment(of: [defaultValueExpectation])

        ubiquitousKeyValueStore.set(externalStoredValue, forKey: keyID)

        await fulfillment(of: [externalStoredValueExpectation])

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation])
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

        await fulfillment(of: [defaultValueExpectation])

        ubiquitousKeyValueStore.set(ubiquitousStoredValue, forKey: keyID)

        await fulfillment(of: [correctValueExpectation])
        
        userDefaults.set(userDefaultsStoredValue, forKey: keyID)
        
        await fulfillment(of: [incorrectValueExpectation], timeout: 1)

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation])
    }
    
    @MainActor
    func test_explicit_nil_defaultViewModifier_default() async {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let userDefaults = UserDefaults.standard
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

        host(view, in: viewController)

        await fulfillment(of: [defaultValueExpectation])
        
        userDefaults.set(externalStoredValue, forKey: keyID)

        await fulfillment(of: [externalStoredValueExpectation])

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation])
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
        
        await fulfillment(of: [defaultValueExpectation])
        
        userDefaults.set(externalStoredValue, forKey: keyID)
        
        await fulfillment(of: [externalStoredValueExpectation])

        view.input.send(internalStoredValue)
        
        await fulfillment(of: [internalStoredValueExpectation])
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

        await fulfillment(of: [defaultValueExpectation])

        ubiquitousKeyValueStore.set(externalStoredValue, forKey: keyID)

        await fulfillment(of: [externalStoredValueExpectation])

        view.input.send(internalStoredValue)

        await fulfillment(of: [internalStoredValueExpectation])
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
            .onChange(of: persistentValue) { newValue in
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

#endif
