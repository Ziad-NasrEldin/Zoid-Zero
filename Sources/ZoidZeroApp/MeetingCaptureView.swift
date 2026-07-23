import SwiftUI
import ZoidZeroCore
import ZoidZeroInfrastructure

struct MeetingCaptureView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    ZStack {
      Sumi.paper.ignoresSafeArea()
      VStack(spacing: 0) {
        header
        Rectangle().fill(Sumi.ink).frame(height: 1)
        content
      }
    }
    .foregroundStyle(Sumi.ink)
    .alert(
      "Could not complete the action",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.clearError() } }
      )
    ) {
      if model.schedulingPrivacyPane != nil {
        Button("Open Privacy Settings") {
          model.openSchedulingPrivacySettings()
        }
      }
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 5) {
        Text("ZOID 0")
          .font(.system(size: 11, weight: .bold, design: .serif))
          .tracking(3)
          .foregroundStyle(Sumi.seal)
        Text("Capture & Time")
          .font(Sumi.display(29))
      }
      Spacer()
      Label("Local only", systemImage: "lock")
        .font(Sumi.body(12))
        .foregroundStyle(Sumi.muted)
    }
    .padding(.horizontal, 36)
    .padding(.vertical, 24)
  }

  @ViewBuilder
  private var content: some View {
    if let receipt = model.receipt {
      ReceiptView(receipt: receipt, done: model.resetReceipt)
    } else if let candidate = model.candidate {
      ConfirmationForm(
        candidate: candidate,
        progress: model.reviewProgress,
        isSaving: model.isSaving,
        confirm: { edited in Task { await model.confirm(edited) } },
        dismiss: model.dismiss
      )
    } else {
      ListeningView(
        health: model.captureHealth,
        report: model.dailyActivityReport,
        selectedDate: model.selectedActivityDate,
        safariState: model.safariWebsiteTrackingState,
        showPreviousDay: model.showPreviousActivityDay,
        showNextDay: model.showNextActivityDay,
        showToday: model.showTodayActivity,
        setCategory: model.setCategory,
        openScreenRecordingSettings: model.openScreenRecordingSettings,
        openSafariExtensionPreferences: model.openSafariExtensionPreferences
      )
    }
  }
}

private struct ListeningView: View {
  let health: CaptureHealthState
  let report: DailyActivityReport
  let selectedDate: Date
  let safariState: SafariWebsiteTrackingState
  let showPreviousDay: () -> Void
  let showNextDay: () -> Void
  let showToday: () -> Void
  let setCategory: (ActivityCategory, ActivitySubject) -> Void
  let openScreenRecordingSettings: () -> Void
  let openSafariExtensionPreferences: () -> Void

  @State private var selectedCategory: ActivityCategory?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        healthPanel
        dailyActivityPanel
        Text("Nothing is added until you review and confirm. Zoid 0 never contacts another person.")
          .font(Sumi.body(12))
          .foregroundStyle(Sumi.muted)
      }
      .padding(36)
    }
  }

  private var healthPanel: some View {
    HStack(alignment: .top, spacing: 22) {
      ZStack {
        Rectangle()
          .fill(Sumi.sealWash)
          .frame(width: 78, height: 78)
        Image(systemName: healthSymbol)
          .font(.system(size: 27, weight: .light))
          .foregroundStyle(Sumi.seal)
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("CAPTURE HEALTH")
          .font(.system(size: 10, weight: .bold, design: .serif))
          .tracking(2)
          .foregroundStyle(Sumi.seal)
        Text(healthTitle)
          .font(Sumi.display(29))
        Text(healthDetail)
          .font(Sumi.body(14))
          .foregroundStyle(Sumi.muted)
          .lineSpacing(3)
        if case .screenRecordingPermissionNeeded = health {
          Button(
            "Open Screen Recording Settings",
            action: openScreenRecordingSettings
          )
          .buttonStyle(InkButtonStyle(accent: true))
          .padding(.top, 6)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(24)
    .background(Sumi.softPaper)
    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
  }

  private var dailyActivityPanel: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 5) {
          Text("WHERE YOUR TIME WENT")
            .font(.system(size: 10, weight: .bold, design: .serif))
            .tracking(2)
            .foregroundStyle(Sumi.seal)
          Text(dateTitle)
            .font(Sumi.display(24))
        }
        Spacer()
        HStack(spacing: 6) {
          dayButton(symbol: "chevron.left", action: showPreviousDay)
          if !isToday {
            Button("Today", action: showToday)
              .buttonStyle(InkButtonStyle(accent: false))
          }
          dayButton(
            symbol: "chevron.right",
            disabled: isToday,
            action: showNextDay
          )
        }
      }

      Rectangle().fill(Sumi.rule).frame(height: 1)

      HStack(alignment: .firstTextBaseline) {
        Text(durationLabel(report.totalDuration))
          .font(Sumi.display(34))
          .monospacedDigit()
        Text("tracked")
          .font(Sumi.body(13))
          .foregroundStyle(Sumi.muted)
        Spacer()
        Text("\(uncategorizedCount) uncategorized")
          .font(Sumi.body(12))
          .foregroundStyle(uncategorizedCount == 0 ? Sumi.muted : Sumi.seal)
      }

      categoryBar

      if report.categoryTotals.isEmpty {
        Text("Time will appear here after you use another application.")
          .font(Sumi.body(14))
          .foregroundStyle(Sumi.muted)
          .padding(.vertical, 12)
      } else {
        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 150), spacing: 10)
          ],
          alignment: .leading,
          spacing: 10
        ) {
          ForEach(report.categoryTotals) { total in
            categorySummary(total)
          }
        }
      }

      safariStatus

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Button("Categorize apps & websites") {
            selectedCategory = uncategorizedCount > 0 ? .uncategorized : nil
          }
          .buttonStyle(InkButtonStyle(accent: false))
          Spacer()
          Text("Choose a category on any row")
            .font(Sumi.body(11))
            .foregroundStyle(Sumi.muted)
        }

        HStack {
          Text("FILTER")
            .font(.system(size: 10, weight: .bold, design: .serif))
            .tracking(2)
            .foregroundStyle(Sumi.seal)
          Spacer()
          Text("\(visibleContributors.count) apps & websites")
            .font(Sumi.body(12))
            .foregroundStyle(Sumi.muted)
        }

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            filterButton(title: "All", category: nil)
            ForEach(ActivityCategory.allCases, id: \.self) { category in
              filterButton(title: category.displayName, category: category)
            }
          }
        }

        Rectangle().fill(Sumi.rule).frame(height: 1)

        if visibleContributors.isEmpty {
          Text("No activity in this category.")
            .font(Sumi.body(14))
            .foregroundStyle(Sumi.muted)
            .padding(.vertical, 8)
        } else {
          ForEach(visibleContributors) { contributor in
            contributorRow(contributor)
          }
        }
      }
    }
    .padding(24)
    .background(Sumi.paper)
    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
  }

  private var categoryBar: some View {
    GeometryReader { geometry in
      HStack(spacing: 2) {
        ForEach(report.categoryTotals) { total in
          categoryColor(total.category)
            .frame(
              width: max(
                2,
                geometry.size.width * total.duration / max(1, report.totalDuration)
              )
            )
        }
      }
    }
    .frame(height: 8)
    .background(Sumi.softPaper)
    .accessibilityLabel("Daily time distribution by category")
  }

  private func categorySummary(_ total: DailyCategoryTotal) -> some View {
    HStack(spacing: 10) {
      Rectangle()
        .fill(categoryColor(total.category))
        .frame(width: 5, height: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(total.category.displayName)
          .font(Sumi.body(13))
        Text(durationLabel(total.duration))
          .font(.system(size: 13, weight: .semibold, design: .serif))
          .monospacedDigit()
      }
      Spacer()
    }
    .padding(10)
    .background(Sumi.softPaper)
  }

  private var safariStatus: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: safariState == .on ? "safari.fill" : "safari")
        .foregroundStyle(safariState == .on ? categoryColor(.browser) : Sumi.muted)
      VStack(alignment: .leading, spacing: 2) {
        Text(safariStatusTitle)
          .font(Sumi.body(13))
        Text(safariStatusDetail)
          .font(Sumi.body(11))
          .foregroundStyle(Sumi.muted)
      }
      Spacer()
      if safariState != .on {
        Button("Set Up Safari", action: openSafariExtensionPreferences)
          .buttonStyle(InkButtonStyle(accent: false))
      }
    }
    .padding(12)
    .background(Sumi.softPaper)
    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
  }

  private func contributorRow(_ contributor: DailyActivityContributor) -> some View {
    VStack(spacing: 7) {
      HStack(spacing: 12) {
        Rectangle()
          .fill(categoryColor(contributor.category))
          .frame(width: 4, height: 30)
        VStack(alignment: .leading, spacing: 2) {
          Text(contributor.displayName)
            .font(Sumi.body(15))
            .lineLimit(1)
          Text(subjectKind(contributor.subject))
            .font(Sumi.body(11))
            .foregroundStyle(Sumi.muted)
        }
        Spacer()
        Menu {
          ForEach(ActivityCategory.allCases, id: \.self) { category in
            Button {
              setCategory(category, contributor.subject)
            } label: {
              if category == contributor.category {
                Label(category.displayName, systemImage: "checkmark")
              } else {
                Text(category.displayName)
              }
            }
          }
        } label: {
          Text(contributor.category.displayName)
            .font(Sumi.body(11))
            .foregroundStyle(Sumi.ink)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Sumi.softPaper)
            .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        Text(durationLabel(contributor.duration))
          .font(.system(size: 13, weight: .semibold, design: .serif))
          .monospacedDigit()
          .frame(minWidth: 52, alignment: .trailing)
      }
      GeometryReader { geometry in
        Rectangle()
          .fill(categoryColor(contributor.category))
          .frame(
            width: geometry.size.width
              * contributor.duration / max(1, report.totalDuration)
          )
      }
      .frame(height: 2)
      .background(Sumi.softPaper)
    }
    .padding(.vertical, 4)
  }

  private func filterButton(
    title: String,
    category: ActivityCategory?
  ) -> some View {
    let isSelected = selectedCategory == category
    return Button {
      selectedCategory = category
    } label: {
      Text(title)
        .font(Sumi.body(12))
        .foregroundStyle(isSelected ? Color.white : Sumi.ink)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(isSelected ? Sumi.ink : Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  private func dayButton(
    symbol: String,
    disabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(width: 32, height: 32)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.35 : 1)
  }

  private var visibleContributors: [DailyActivityContributor] {
    report.contributors(in: selectedCategory)
  }

  private var uncategorizedCount: Int {
    report.contributors(in: .uncategorized).count
  }

  private var isToday: Bool {
    Calendar.current.isDateInToday(selectedDate)
  }

  private var dateTitle: String {
    if isToday { return "Today" }
    return selectedDate.formatted(
      Date.FormatStyle()
        .weekday(.wide)
        .month(.abbreviated)
        .day()
    )
  }

  private var safariStatusTitle: String {
    switch safariState {
    case .on: "Safari websites are included"
    case .permissionNeeded: "Allow website access in Safari"
    case .extensionDisabled: "Safari website tracking is off"
    case .unavailable: "Safari website tracking is unavailable"
    }
  }

  private var safariStatusDetail: String {
    switch safariState {
    case .on:
      "Only the website domain is saved. Page paths, searches, titles, and content stay private."
    case .permissionNeeded:
      "Enable the Zoid 0 extension and allow access to include website domains."
    case .extensionDisabled:
      "Enable the Zoid 0 extension to separate Safari time by website."
    case .unavailable:
      "Safari time remains counted under the Safari application."
    }
  }

  private func subjectKind(_ subject: ActivitySubject) -> String {
    switch subject {
    case .application: "Application"
    case .website: "Website domain"
    }
  }

  private func categoryColor(_ category: ActivityCategory) -> Color {
    switch category {
    case .work: Color(red: 0.18, green: 0.34, blue: 0.50)
    case .communication: Color(red: 0.17, green: 0.48, blue: 0.42)
    case .social: Color(red: 0.68, green: 0.31, blue: 0.42)
    case .gaming: Color(red: 0.48, green: 0.31, blue: 0.62)
    case .media: Color(red: 0.78, green: 0.45, blue: 0.17)
    case .utilities: Color(red: 0.36, green: 0.40, blue: 0.43)
    case .browser: Color(red: 0.17, green: 0.48, blue: 0.63)
    case .uncategorized: Sumi.rule
    }
  }

  private var healthTitle: String {
    switch health {
    case .monitoring:
      "Monitoring"
    case .analyzingChangedScreen:
      "Analyzing changed screen"
    case .pausedWhileIdle:
      "Paused while idle"
    case .screenRecordingPermissionNeeded:
      "Screen Recording permission needed"
    case .captureError:
      "Capture error"
    }
  }

  private var healthDetail: String {
    switch health {
    case .monitoring:
      "Changed screens are checked locally. Text recognition runs only when the screen meaningfully changes."
    case .analyzingChangedScreen:
      "Apple Vision is reading the newest changed screen locally in English and Arabic when supported."
    case .pausedWhileIdle:
      "Screen sampling and application time attribution are paused while the Mac is idle."
    case .screenRecordingPermissionNeeded:
      "Allow Zoid 0 in System Settings to begin local screen observation. The app will not keep asking after denial."
    case .captureError(let message):
      message
    }
  }

  private var healthSymbol: String {
    switch health {
    case .monitoring:
      "eye"
    case .analyzingChangedScreen:
      "text.viewfinder"
    case .pausedWhileIdle:
      "pause"
    case .screenRecordingPermissionNeeded:
      "rectangle.inset.filled.badge.record"
    case .captureError:
      "exclamationmark.triangle"
    }
  }

  private func durationLabel(_ duration: TimeInterval) -> String {
    if duration < 60 {
      return "\(max(0, Int(duration)))s"
    }
    let minutes = Int(duration / 60)
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 {
      return "\(minutes)m"
    }
    if remainder == 0 {
      return "\(hours)h"
    }
    return "\(hours)h \(remainder)m"
  }
}

private struct ConfirmationForm: View {
  @State private var title: String
  @State private var person: String
  @State private var start: Date
  @State private var duration: Int

  let original: MeetingCandidate
  let progress: String?
  let isSaving: Bool
  let confirm: (MeetingCandidate) -> Void
  let dismiss: () -> Void

  init(
    candidate: MeetingCandidate,
    progress: String?,
    isSaving: Bool,
    confirm: @escaping (MeetingCandidate) -> Void,
    dismiss: @escaping () -> Void
  ) {
    original = candidate
    self.progress = progress
    self.isSaving = isSaving
    self.confirm = confirm
    self.dismiss = dismiss
    _title = State(initialValue: candidate.title)
    _person = State(initialValue: candidate.person)
    _start = State(initialValue: candidate.start)
    _duration = State(initialValue: candidate.durationMinutes)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("POSSIBLE AGREEMENT")
              .font(.system(size: 10, weight: .bold, design: .serif))
              .tracking(2)
              .foregroundStyle(Sumi.seal)
            Spacer()
            if let progress {
              Text(progress)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
            }
          }
          Text("Confirm the meeting")
            .font(Sumi.display(34))
          Text(
            "Review every detail. Confirming creates one personal Calendar event and one Reminder. No invitation or message is sent."
          )
          .font(Sumi.body(14))
          .foregroundStyle(Sumi.muted)
          .lineSpacing(3)
        }

        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 20) {
          field("Meeting title", uncertain: original.uncertainFields.contains(.title)) {
            TextField("", text: $title)
          }
          field("Person", uncertain: original.uncertainFields.contains(.person)) {
            TextField("", text: $person)
          }
          field(
            "Date and time",
            uncertain: original.uncertainFields.contains(.date)
              || original.uncertainFields.contains(.time)
              || original.uncertainFields.contains(.timeZone)
          ) {
            DatePicker("", selection: $start)
              .labelsHidden()
              .datePickerStyle(.field)
          }
          field("Duration", uncertain: original.uncertainFields.contains(.duration)) {
            Picker("", selection: $duration) {
              ForEach([15, 30, 45, 60, 90, 120], id: \.self) {
                Text("\($0) minutes").tag($0)
              }
            }
            .labelsHidden()
          }
        }

        HStack {
          Label("No attendees will be added", systemImage: "person.crop.circle.badge.xmark")
            .font(Sumi.body(12))
            .foregroundStyle(Sumi.muted)
          Spacer()
          Button("Dismiss", action: dismiss)
            .buttonStyle(InkButtonStyle(accent: false))
          Button(isSaving ? "Adding..." : "Confirm and add") {
            confirm(
              MeetingCandidate(
                id: original.id,
                title: title,
                person: person,
                start: start,
                durationMinutes: duration,
                sourceFingerprint: original.sourceFingerprint,
                detectorSource: original.detectorSource,
                uncertainFields: []
              )
            )
          }
          .buttonStyle(InkButtonStyle(accent: true))
          .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .padding(36)
    }
  }

  private func field<Content: View>(
    _ label: String,
    uncertain: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        InkFieldLabel(text: label)
        if uncertain {
          Text("NEEDS REVIEW")
            .font(.system(size: 9, weight: .bold, design: .serif))
            .tracking(1)
            .foregroundStyle(Sumi.seal)
        }
      }
      content()
        .textFieldStyle(.plain)
        .font(Sumi.body(15))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
    }
  }
}

private struct ReceiptView: View {
  let receipt: SchedulingReceipt
  let done: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      Text("ADDED")
        .font(.system(size: 10, weight: .bold, design: .serif))
        .tracking(2)
        .foregroundStyle(Sumi.seal)
      Text("Meeting secured")
        .font(Sumi.display(34))
      VStack(alignment: .leading, spacing: 12) {
        receiptLine("Apple Calendar", complete: receipt.eventCreated)
        receiptLine("Apple Reminders", complete: receipt.reminderCreated)
      }
      .padding(22)
      .frame(width: 360)
      .background(Sumi.softPaper)
      .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
      Text("No attendee, invitation, email, or client message was created.")
        .font(Sumi.body(13))
        .foregroundStyle(Sumi.muted)
      Button("Done", action: done)
        .buttonStyle(InkButtonStyle(accent: true))
      Spacer()
    }
    .padding(36)
  }

  private func receiptLine(_ title: String, complete: Bool) -> some View {
    HStack {
      Text(title).font(Sumi.body(15))
      Spacer()
      Image(systemName: complete ? "checkmark" : "xmark")
        .foregroundStyle(complete ? Sumi.ink : Sumi.seal)
    }
  }
}
