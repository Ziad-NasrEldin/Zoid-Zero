//
//  AtollXPCConnectionManager.swift
//  AtollExtensionKit
//
//  Manages XPC connection to Atoll service.
//

import AppKit
import Foundation

final class AtollXPCConnectionManager: NSObject, @unchecked Sendable {
    private static let serviceName = "com.ebullioscopic.Atoll.xpc"
    private static let atollBundleIdentifier = "com.ebullioscopic.Atoll"
    private var connection: NSXPCConnection?
    private let queue = DispatchQueue(label: "com.atoll.xpc.connection")
    
    var onAuthorizationChange: ((Bool) -> Void)?
    var onActivityDismiss: ((String) -> Void)?
    var onWidgetDismiss: ((String) -> Void)?
    var onNotchExperienceDismiss: ((String) -> Void)?
    var onZoidMeetingAction: ((String, String) -> Void)?
    
    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }
    
    var isAtollInstalled: Bool {
        if isAtollRunning {
            return true
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.atollBundleIdentifier) {
            return FileManager.default.fileExists(atPath: appURL.path)
        }

        let fallbackPaths = [
            "/Applications/Atoll.app",
            NSString(string: NSHomeDirectory()).appendingPathComponent("Applications/Atoll.app")
        ]
        return fallbackPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private var isAtollRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.atollBundleIdentifier).isEmpty
    }
    
    // MARK: - Connection Management
    
    private func getConnection() throws -> NSXPCConnection {
        if let existing = connection {
            return existing
        }
        
        guard isAtollInstalled else {
            throw AtollExtensionKitError.atollNotInstalled
        }
        
        let newConnection = NSXPCConnection(machServiceName: Self.serviceName, options: [])
        newConnection.remoteObjectInterface = NSXPCInterface(with: AtollXPCServiceProtocol.self)
        newConnection.exportedInterface = NSXPCInterface(with: AtollXPCClientProtocol.self)
        newConnection.exportedObject = self
        
        newConnection.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        
        newConnection.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        
        newConnection.resume()
        connection = newConnection
        return newConnection
    }
    
    private func getService(
        onError: ((Error) -> Void)? = nil
    ) throws -> AtollXPCServiceProtocol {
        let connection = try getConnection()
        
        guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
            print("XPC Error: \(error)")
            onError?(error)
        }) as? AtollXPCServiceProtocol else {
            throw AtollExtensionKitError.serviceUnavailable
        }
        
        return service
    }
    
    // MARK: - Service Methods
    
    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let gate = XPCContinuationGate(continuation)
            do {
                let service = try getService { error in
                    gate.resume(
                        throwing: AtollExtensionKitError.connectionFailed(
                            underlying: error
                        )
                    )
                }
                service.requestAuthorization(bundleIdentifier: bundleIdentifier) { authorized, error in
                    if let error {
                        gate.resume(
                            throwing: AtollExtensionKitError.connectionFailed(
                                underlying: error
                            )
                        )
                    } else {
                        gate.resume(returning: authorized)
                    }
                }
            } catch {
                gate.resume(throwing: error)
            }
        }
    }
    
    func checkAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let service = try getService()
                service.checkAuthorization(bundleIdentifier: bundleIdentifier) { authorized in
                    continuation.resume(returning: authorized)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func getVersion() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let service = try getService()
                service.getVersion { version in
                    continuation.resume(returning: version)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func presentLiveActivity(_ descriptor: AtollLiveActivityDescriptor) async throws {
        let data = try JSONEncoder().encode(descriptor)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.presentLiveActivity(descriptorData: data) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to present activity"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func updateLiveActivity(_ descriptor: AtollLiveActivityDescriptor) async throws {
        let data = try JSONEncoder().encode(descriptor)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.updateLiveActivity(descriptorData: data) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to update activity"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func dismissLiveActivity(activityID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.dismissLiveActivity(activityID: activityID, bundleIdentifier: bundleIdentifier) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to dismiss activity"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func presentLockScreenWidget(_ descriptor: AtollLockScreenWidgetDescriptor) async throws {
        let data = try JSONEncoder().encode(descriptor)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.presentLockScreenWidget(descriptorData: data) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to present widget"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func updateLockScreenWidget(_ descriptor: AtollLockScreenWidgetDescriptor) async throws {
        let data = try JSONEncoder().encode(descriptor)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.updateLockScreenWidget(descriptorData: data) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to update widget"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func dismissLockScreenWidget(widgetID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.dismissLockScreenWidget(widgetID: widgetID, bundleIdentifier: bundleIdentifier) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to dismiss widget"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func presentNotchExperience(_ descriptor: AtollNotchExperienceDescriptor) async throws {
        let data = try JSONEncoder().encode(descriptor)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.presentNotchExperience(descriptorData: data) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to present notch experience"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func updateNotchExperience(_ descriptor: AtollNotchExperienceDescriptor) async throws {
        let data = try JSONEncoder().encode(descriptor)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.updateNotchExperience(descriptorData: data) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to update notch experience"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func dismissNotchExperience(experienceID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let service = try getService()
                service.dismissNotchExperience(experienceID: experienceID, bundleIdentifier: bundleIdentifier) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? AtollExtensionKitError.unknown("Failed to dismiss notch experience"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func presentZoidMeetingPrompt(_ prompt: ZoidMeetingPrompt) async throws {
        let data = try JSONEncoder().encode(prompt)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = XPCContinuationGate(continuation)
            do {
                let service = try getService { error in
                    gate.resume(
                        throwing: AtollExtensionKitError.connectionFailed(
                            underlying: error
                        )
                    )
                }
                service.presentZoidMeetingPrompt(
                    promptData: data,
                    bundleIdentifier: bundleIdentifier
                ) { success, error in
                    if success {
                        gate.resume(returning: ())
                    } else {
                        gate.resume(
                            throwing: error
                                ?? AtollExtensionKitError.unknown("Failed to present Zoid meeting prompt")
                        )
                    }
                }
            } catch {
                gate.resume(throwing: error)
            }
        }
    }

    func reportZoidMeetingSaveResult(
        promptID: String,
        result: ZoidMeetingSaveResult
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = XPCContinuationGate(continuation)
            do {
                let service = try getService { error in
                    gate.resume(
                        throwing: AtollExtensionKitError.connectionFailed(
                            underlying: error
                        )
                    )
                }
                service.reportZoidMeetingSaveResult(
                    promptID: promptID,
                    resultRawValue: result.rawValue,
                    bundleIdentifier: bundleIdentifier
                ) { success, error in
                    if success {
                        gate.resume(returning: ())
                    } else {
                        gate.resume(
                            throwing: error
                                ?? AtollExtensionKitError.unknown("Failed to report Zoid meeting result")
                        )
                    }
                }
            } catch {
                gate.resume(throwing: error)
            }
        }
    }
    
    deinit {
        connection?.invalidate()
    }
}

private final class XPCContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        takeContinuation()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}

// MARK: - Client Protocol Implementation

extension AtollXPCConnectionManager: AtollXPCClientProtocol {
    func authorizationDidChange(isAuthorized: Bool) {
        onAuthorizationChange?(isAuthorized)
    }
    
    func activityDidDismiss(activityID: String) {
        onActivityDismiss?(activityID)
    }
    
    func widgetDidDismiss(widgetID: String) {
        onWidgetDismiss?(widgetID)
    }
    
    func notchExperienceDidDismiss(experienceID: String) {
        onNotchExperienceDismiss?(experienceID)
    }

    func zoidMeetingActionSelected(promptID: String, actionRawValue: String) {
        onZoidMeetingAction?(promptID, actionRawValue)
    }
}
