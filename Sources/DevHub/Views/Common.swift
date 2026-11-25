import SwiftUI
import AppKit

/// Brings the app forward when opening a window from the menu bar panel.
func bringToFront() {
    NSApp.activate(ignoringOtherApps: true)
}

extension View {
    /// Hebrew UI direction.
    func rtl() -> some View { environment(\.layoutDirection, .rightToLeft) }
    /// Code, paths and logs always read left-to-right.
    func ltr() -> some View { environment(\.layoutDirection, .leftToRight) }
}

/// An error message with an expandable, copyable "details" section.
struct ErrorDetails: View {
    let message: String
    let details: String?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message).font(.caption)
            if let details, !details.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView {
                            Text(details)
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .ltr()
                        }
                        .frame(maxHeight: 120)
                        Button("העתק") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(details, forType: .string)
                        }
                        .controlSize(.small)
                    }
                } label: {
                    Text("פרטים").font(.caption)
                }
            }
        }
    }
}

/// "1:05" style elapsed timer.
struct ElapsedText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
