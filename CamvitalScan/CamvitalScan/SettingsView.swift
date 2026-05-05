import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var healthKit: HealthKitManager

    var body: some View {
        NavigationStack {
            ZStack {
                PulseTheme.screenBackground.ignoresSafeArea()

                Form {
                    Section {
                        Stepper(value: $settings.age, in: 12...95) {
                            Text("Age: \(settings.age)")
                        }
                        Text("Used for heart-rate zone labels (220 − age estimate).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Profile")
                    }

                    Section {
                        Toggle("Save to Apple Health", isOn: $settings.saveToHealth)
                            .disabled(!healthKit.isAvailable)

                        Button("Connect Apple Health") {
                            Task { await healthKit.requestAuthorization() }
                        }
                        .disabled(!healthKit.isAvailable)

                        if !healthKit.isAvailable {
                            Label("Health data export is not available on this device.", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Export is optional and permission-based. Your scan history stays on device unless you choose to share a reading.")
                    }

                    Section {
                        guidanceRow(
                            icon: "camera.metering.center.weighted",
                            title: "Camera-based scan",
                            detail: "Camvital uses optical color changes from your fingertip to estimate pulse."
                        )

                        guidanceRow(
                            icon: "hand.raised",
                            title: "Best conditions",
                            detail: "Warm hands, gentle pressure, and a steady grip improve signal quality."
                        )

                        guidanceRow(
                            icon: "cross.case",
                            title: "Wellness only",
                            detail: "Not a medical device. Seek professional care for symptoms or health concerns."
                        )
                    } header: {
                        Text("About")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
    }

    private func guidanceRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(PulseTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
