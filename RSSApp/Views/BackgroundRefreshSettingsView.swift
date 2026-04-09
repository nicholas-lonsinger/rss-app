import SwiftUI
import os

/// Settings sub-page for configuring periodic background feed refresh.
/// Pushed from the top-level `SettingsView`.
struct BackgroundRefreshSettingsView: View {

    private static let logger = Logger(category: "BackgroundRefreshSettingsView")

    @State private var isEnabled: Bool
    @State private var interval: BackgroundRefreshInterval
    @State private var networkRequirement: BackgroundRefreshNetworkRequirement
    @State private var powerRequirement: BackgroundRefreshPowerRequirement

    /// Surfaces `BGTaskScheduler.submit(_:)` failures triggered by the user's
    /// own setting changes. The most common cause is Background App Refresh
    /// being disabled in iOS Settings → General, which causes submit to throw
    /// with `BGTaskSchedulerErrorDomain` code 1 ("unavailable"). The user's
    /// in-app preference is intentionally NOT reverted on failure — iOS
    /// convention is to keep the user's declared intent and tell them where
    /// to fix the underlying OS-level condition.
    @State private var scheduleError: Error?

    init() {
        _isEnabled = State(initialValue: BackgroundRefreshSettings.isEnabled)
        _interval = State(initialValue: BackgroundRefreshSettings.interval)
        _networkRequirement = State(initialValue: BackgroundRefreshSettings.networkRequirement)
        _powerRequirement = State(initialValue: BackgroundRefreshSettings.powerRequirement)
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $isEnabled) {
                    Label("Background Refresh", systemImage: "arrow.clockwise")
                }
                .onChange(of: isEnabled) { _, newValue in
                    BackgroundRefreshSettings.isEnabled = newValue
                    if newValue {
                        scheduleOrReportError()
                    } else {
                        BackgroundRefreshScheduler.cancelAll()
                    }
                }
            } footer: {
                Text("When enabled, feeds refresh periodically in the background so new articles appear without pull-to-refresh. The system chooses the exact timing based on your usage and the constraints below.")
            }

            Section {
                ForEach(BackgroundRefreshInterval.allCases) { option in
                    Button {
                        interval = option
                        BackgroundRefreshSettings.interval = option
                        scheduleOrReportError()
                    } label: {
                        HStack {
                            Text(option.displayLabel)
                                .foregroundStyle(.primary)
                            Spacer()
                            if option == interval {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } header: {
                Text("Refresh Interval")
            } footer: {
                Text("Minimum time between refreshes. The system may delay refreshes based on battery, network, and usage patterns.")
            }
            .disabled(!isEnabled)

            Section {
                Picker("Network", selection: $networkRequirement) {
                    ForEach(BackgroundRefreshNetworkRequirement.allCases) { option in
                        Text(option.displayLabel).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: networkRequirement) { _, newValue in
                    BackgroundRefreshSettings.networkRequirement = newValue
                    scheduleOrReportError()
                }
            } header: {
                Text("Network")
            } footer: {
                Text("Select \"Wi-Fi Only\" to avoid using cellular data for background refresh.")
            }
            .disabled(!isEnabled)

            Section {
                Picker("Power", selection: $powerRequirement) {
                    ForEach(BackgroundRefreshPowerRequirement.allCases) { option in
                        Text(option.displayLabel).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: powerRequirement) { _, newValue in
                    BackgroundRefreshSettings.powerRequirement = newValue
                    scheduleOrReportError()
                }
            } header: {
                Text("Power")
            } footer: {
                Text("Select \"Charging Only\" to reserve background refresh for when your device is plugged in. The system will not run background refresh on battery power when this is selected.")
            }
            .disabled(!isEnabled)
        }
        .navigationTitle("Background Refresh")
        .alert(
            "Background Refresh Unavailable",
            isPresented: Binding(
                get: { scheduleError != nil },
                set: { if !$0 { scheduleError = nil } }
            ),
            presenting: scheduleError
        ) { _ in
            Button("OK") { scheduleError = nil }
        } message: { _ in
            Text("Background refresh couldn't be scheduled. Make sure Background App Refresh is enabled for this app in Settings → General → Background App Refresh.")
        }
    }

    // MARK: - Helpers

    /// Attempts to schedule the next refresh and surfaces any submission
    /// failure via the `scheduleError` alert binding.
    private func scheduleOrReportError() {
        do {
            try BackgroundRefreshScheduler.scheduleNextRefresh()
        } catch {
            Self.logger.error("User-initiated schedule change failed: \(error, privacy: .public)")
            scheduleError = error
        }
    }
}
