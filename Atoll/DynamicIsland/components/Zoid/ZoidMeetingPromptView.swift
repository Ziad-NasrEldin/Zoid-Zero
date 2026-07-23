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
import SwiftUI

struct ZoidMeetingPromptView: View {
    let prompt: ZoidMeetingPrompt
    let phase: ZoidMeetingPromptPhase
    let onAction: (ZoidMeetingAction) -> Void

    private var isDecisionEnabled: Bool {
        phase == .awaitingDecision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 0)
                if phase == .saving {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if phase == .awaitingDecision || phase == .saving {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if shouldShowParticipant {
                            Text(prompt.participantName ?? "")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Text(dateLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(timeLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Button("Dismiss") {
                            onAction(.dismiss)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                        .disabled(!isDecisionEnabled)
                        .accessibilityIdentifier("ZoidMeetingDismiss")

                        Button("Confirm") {
                            onAction(.confirm)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.blue, in: Capsule())
                        .contentShape(Capsule())
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isDecisionEnabled)
                        .accessibilityIdentifier("ZoidMeetingConfirm")
                    }
                    .controlSize(.regular)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 430, minHeight: 150, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting detected")
        .accessibilityIdentifier("ZoidMeetingPrompt")
    }

    private var shouldShowParticipant: Bool {
        guard let participant = prompt.participantName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !participant.isEmpty else {
            return false
        }
        return !prompt.title.localizedCaseInsensitiveContains(participant)
    }

    private var statusTitle: String {
        switch phase {
        case .idle, .awaitingDecision:
            return "Meeting detected"
        case .saving:
            return "Saving meeting"
        case .saved:
            return "Meeting saved"
        case .failed:
            return "Couldn’t save meeting"
        }
    }

    private var statusIcon: String {
        switch phase {
        case .idle, .awaitingDecision, .saving:
            return "calendar.badge.clock"
        case .saved:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch phase {
        case .saved:
            return .green
        case .failed:
            return .orange
        case .idle, .awaitingDecision, .saving:
            return .blue
        }
    }

    private var dateLine: String {
        formatter(dateStyle: .medium, timeStyle: .none).string(from: prompt.startDate)
    }

    private var timeLine: String {
        let formatter = formatter(dateStyle: .none, timeStyle: .short)
        let duration = max(1, Int(prompt.endDate.timeIntervalSince(prompt.startDate) / 60))
        return "\(formatter.string(from: prompt.startDate)) - \(formatter.string(from: prompt.endDate)) · \(duration) min"
    }

    private func formatter(
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = TimeZone(identifier: prompt.timeZoneIdentifier)
        return formatter
    }
}
