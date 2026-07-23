/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AtollExtensionKit
import Foundation

@MainActor
final class ZoidMeetingPromptManager: ObservableObject {
    static let shared = ZoidMeetingPromptManager()

    @Published private(set) var prompt: ZoidMeetingPrompt?
    @Published private(set) var phase: ZoidMeetingPromptPhase = .idle
    @Published private(set) var closeSequence = 0

    private var stateMachine = ZoidMeetingPromptStateMachine()
    private var bundleIdentifier: String?
    private var timeoutTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var distributedObservers: [NSObjectProtocol] = []

    private init() {
        let center = DistributedNotificationCenter.default()
        distributedObservers.append(
            center.addObserver(
                forName: ZoidMeetingDistributedBridge.promptNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let (prompt, bundleIdentifier)
                        = ZoidMeetingDistributedBridge.decodePrompt(notification)
                else {
                    return
                }
                Task { @MainActor in
                    try? self?.present(prompt, bundleIdentifier: bundleIdentifier)
                }
            }
        )
        distributedObservers.append(
            center.addObserver(
                forName: ZoidMeetingDistributedBridge.saveResultNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let (payload, bundleIdentifier)
                        = ZoidMeetingDistributedBridge.decodeSaveResult(notification)
                else {
                    return
                }
                Task { @MainActor in
                    guard self?.bundleIdentifier == bundleIdentifier else { return }
                    try? self?.reportSaveResult(
                        promptID: payload.promptID,
                        result: payload.result
                    )
                }
            }
        )
    }

    func present(
        _ prompt: ZoidMeetingPrompt,
        bundleIdentifier: String
    ) throws {
        guard prompt.isValid else {
            throw ZoidMeetingPromptError.invalidPrompt
        }

        let effect = stateMachine.handle(.present(prompt))
        guard effect != .busy else {
            throw ZoidMeetingPromptError.busy
        }

        timeoutTask?.cancel()
        closeTask?.cancel()
        self.bundleIdentifier = bundleIdentifier
        publishState()
    }

    func didBecomeVisible() {
        guard phase == .awaitingDecision, timeoutTask == nil else { return }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            await self?.select(.timeout)
        }
    }

    func select(_ action: ZoidMeetingAction) {
        guard let prompt, let bundleIdentifier else { return }
        timeoutTask?.cancel()
        timeoutTask = nil

        let effect = stateMachine.handle(.select(action))
        publishState()
        handle(
            effect,
            promptID: prompt.id,
            bundleIdentifier: bundleIdentifier
        )
    }

    func reportSaveResult(
        promptID: String,
        result: ZoidMeetingSaveResult
    ) throws {
        guard prompt?.id == promptID, phase == .saving else {
            throw ZoidMeetingPromptError.missingPrompt
        }

        let effect = stateMachine.handle(.saveResult(result))
        publishState()
        handle(
            effect,
            promptID: promptID,
            bundleIdentifier: bundleIdentifier ?? ""
        )
    }

    private func handle(
        _ effect: ZoidMeetingPromptEffect,
        promptID: String,
        bundleIdentifier: String
    ) {
        switch effect {
        case .send(let action):
            try? ZoidMeetingDistributedBridge.postAction(
                promptID: promptID,
                action: action,
                bundleIdentifier: bundleIdentifier
            )
            ExtensionXPCServiceHost.shared.notifyZoidMeetingAction(
                bundleIdentifier: bundleIdentifier,
                promptID: promptID,
                action: action
            )
        case .sendAndClose(let action):
            try? ZoidMeetingDistributedBridge.postAction(
                promptID: promptID,
                action: action,
                bundleIdentifier: bundleIdentifier
            )
            ExtensionXPCServiceHost.shared.notifyZoidMeetingAction(
                bundleIdentifier: bundleIdentifier,
                promptID: promptID,
                action: action
            )
            close()
        case .close(let delay):
            closeTask?.cancel()
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.close()
            }
        case .none, .busy:
            break
        }
    }

    private func close() {
        timeoutTask?.cancel()
        closeTask?.cancel()
        timeoutTask = nil
        closeTask = nil
        bundleIdentifier = nil
        _ = stateMachine.handle(.reset)
        publishState()
        closeSequence += 1
    }

    private func publishState() {
        prompt = stateMachine.prompt
        phase = stateMachine.phase
    }
}

enum ZoidMeetingPromptError: LocalizedError {
    case busy
    case invalidPrompt
    case missingPrompt

    var errorDescription: String? {
        switch self {
        case .busy:
            return "A Zoid meeting prompt is already visible."
        case .invalidPrompt:
            return "The Zoid meeting prompt is invalid."
        case .missingPrompt:
            return "The Zoid meeting prompt is no longer active."
        }
    }
}
