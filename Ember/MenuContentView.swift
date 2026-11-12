import EmberKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            modePicker
            snoozeRow
            Divider()
            toggles
            if needsAttention {
                Divider()
                attention
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.reconcileSoon() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: model.poke) {
                MascotView(mood: model.mood, light: model.decision.target, size: 56)
                    .id(model.mood)
            }
            .buttonStyle(.plain)
            .help("Poke Ember")

            VStack(alignment: .leading, spacing: 4) {
                Text("Ember").font(.headline)
                Text(model.headline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.statusText)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(statusTint.opacity(0.18)))
                    .foregroundStyle(statusTint)
            }
        }
    }

    private var statusTint: Color {
        switch model.decision.target {
        case .off: return .secondary
        case .green: return .green
        case .amber, .system: return .orange
        }
    }

    // MARK: Mode and snooze

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode").font(.caption).foregroundStyle(.secondary)
            Picker("Mode", selection: Binding(get: { model.settings.mode }, set: { model.setMode($0) })) {
                ForEach(LightMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(modeHint).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var modeHint: String {
        switch model.settings.mode {
        case .auto: return "Follows your Focus filters, snoozes and schedule."
        case .alwaysOff: return "Off, full stop (low-battery guard still applies)."
        case .alwaysOn: return "macOS's normal amber and green, whatever Focus says."
        }
    }

    @ViewBuilder
    private var snoozeRow: some View {
        if let snooze = model.settings.snooze, snooze.isActive(at: Date()) {
            HStack {
                Label("Off until \(Personality.shortTime(snooze.until))", systemImage: "moon.zzz.fill")
                    .font(.callout)
                Spacer()
                Button("Wake up", action: model.cancelSnooze)
            }
        } else {
            HStack(spacing: 8) {
                Button { model.snooze(minutes: 60) } label: {
                    Label("Off for 1 hour", systemImage: "timer")
                }
                Button(action: model.snoozeUntilMorning) {
                    Label("Off until morning", systemImage: "sunrise")
                }
            }
            .controlSize(.small)
            .disabled(model.settings.mode == .alwaysOff)
        }
    }

    // MARK: Toggles

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { model.settings.lowBatteryGuardEnabled },
                set: { model.settings.lowBatteryGuardEnabled = $0 }
            )) {
                HStack(spacing: 4) {
                    Text("Stay lit when battery is under")
                    Picker("", selection: Binding(
                        get: { model.settings.lowBatteryThreshold },
                        set: { model.settings.lowBatteryThreshold = $0 }
                    )) {
                        ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Toggle("Lights-out schedule", isOn: Binding(
                get: { model.settings.schedule.isEnabled },
                set: { model.settings.schedule.isEnabled = $0 }
            ))
            if model.settings.schedule.isEnabled {
                HStack {
                    DatePicker("From", selection: minutesBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("to", selection: minutesBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                }
                .datePickerStyle(.field)
                .font(.callout)
                .padding(.leading, 18)
            }

            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<LightsOutSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = model.settings.schedule[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                model.settings.schedule[keyPath: keyPath] = LightsOutSchedule.minutesIntoDay(date, calendar: .current)
            }
        )
    }

    // MARK: Problems

    private var needsAttention: Bool {
        model.problem != nil || model.aldenteRunning || model.lastError != nil
    }

    @ViewBuilder
    private var attention: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.problem {
            case .helperNeedsApproval:
                Label("Ember's helper needs your OK in Login Items.", systemImage: "lock.shield")
                Button("Open Login Items", action: model.approveHelper)
            case .helperUnavailable:
                Label("Ember's helper isn't running.", systemImage: "exclamationmark.triangle")
                HStack {
                    Button("Install helper", action: model.approveHelper)
                    Button("Reinstall", action: model.reinstallHelper)
                }
            case .unsupportedMac:
                Label("No MagSafe light found on this Mac.", systemImage: "questionmark.circle")
            case .writeFailed, .none:
                EmptyView()
            }
            if model.aldenteRunning {
                Label("AlDente is running. If its MagSafe light setting is on, you two will argue. Turn one off.", systemImage: "exclamationmark.bubble")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .controlSize(.small)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button(action: model.wave) {
                Label("Wave", systemImage: "hand.wave")
            }
            .disabled(model.isWaving || model.helperState != .enabled)
            .help("Blink the MagSafe light so you can find the cable")

            Button {
                model.openFocusSettings()
            } label: {
                Label("Focus…", systemImage: "moon.circle")
            }
            .help("In each Focus: Focus Filters › Add Filter › Ember")

            Spacer()

            Menu {
                Button("About Ember") { Maintenance.showAbout() }
                Button("Check for Updates…") { Maintenance.checkForUpdates() }
                Button("Ember on GitHub") { NSWorkspace.shared.open(EmberLinks.home) }
                Divider()
                Button("Welcome & setup…") {
                    openWindow(id: "welcome")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Reinstall helper", action: model.reinstallHelper)
                Button("Uninstall Ember…") { Maintenance.uninstall(model: model) }
                Divider()
                Text("Ember \(EmberLinks.appVersion)")
                Button("Quit Ember") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .controlSize(.small)
    }
}
