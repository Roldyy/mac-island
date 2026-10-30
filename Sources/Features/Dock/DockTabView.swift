import SwiftUI

struct DockTabView: View {
    let settings: DockSettings
    let permissions: DockPermissionChecking

    @State private var minimize: Bool
    @State private var hide: Bool
    @State private var cycle: Bool
    @State private var preview: Bool
    @State private var delay: Double
    @State private var accessibility = false
    @State private var screenRecording = false

    init(settings: DockSettings, permissions: DockPermissionChecking) {
        self.settings = settings
        self.permissions = permissions
        _minimize = State(initialValue: settings.clickMinimize)
        _hide = State(initialValue: settings.clickHide)
        _cycle = State(initialValue: settings.clickCycle)
        _preview = State(initialValue: settings.previewEnabled)
        _delay = State(initialValue: Double(settings.previewDelayMilliseconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dock click").font(.headline)
            Toggle("Minimize the frontmost app, click again to restore", isOn: $minimize)
            Toggle("Hide the frontmost app instead (when minimize is off)", isOn: $hide)
            Toggle("Cycle through several windows", isOn: $cycle)

            Divider().overlay(.white.opacity(0.2))

            Toggle("Window preview on hover", isOn: $preview).font(.headline)
            HStack {
                Text("Delay")
                Slider(value: $delay, in: Double(DockSettings.delayRange.lowerBound)...Double(DockSettings.delayRange.upperBound), step: 50)
                    .accessibilityLabel("Preview delay")
                    .accessibilityValue("\(Int(delay)) milliseconds")
                Text("\(Int(delay)) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
            }
            .disabled(!preview)

            Divider().overlay(.white.opacity(0.2))

            permissionRow(PermissionLines.accessibility(granted: accessibility), granted: accessibility,
                          button: "Grant", action: permissions.requestAccessibility)
            permissionRow(PermissionLines.screenRecording(granted: screenRecording), granted: screenRecording,
                          button: "Grant", action: permissions.requestScreenRecording)
            if !screenRecording {
                Text("Without it the preview lists window titles only.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(.black)
        .onAppear(perform: refresh)
        .onChange(of: minimize) { settings.clickMinimize = minimize }
        .onChange(of: hide) { settings.clickHide = hide }
        .onChange(of: cycle) { settings.clickCycle = cycle }
        .onChange(of: preview) { settings.previewEnabled = preview }
        .onChange(of: delay) { settings.previewDelayMilliseconds = Int(delay) }
    }

    private func refresh() {
        accessibility = permissions.accessibilityGranted
        screenRecording = permissions.screenRecordingGranted
    }

    private func permissionRow(_ line: String, granted: Bool, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .foregroundStyle(granted ? .green : .yellow)
                .accessibilityHidden(true)
            Text(line).font(.callout)
            Spacer()
            if !granted {
                Button(button) { action(); refresh() }.controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
