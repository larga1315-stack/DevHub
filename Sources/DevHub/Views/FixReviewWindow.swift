import SwiftUI
import AppKit
import DevHubCore

struct FixReviewWindow: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let id = hub.reviewProjectID,
           let session = hub.fixes[id],
           let project = hub.store.project(id) {
            FixReviewContent(project: project, session: session) {
                hub.approveFix(projectID: id)
                dismiss()
            } onReject: {
                hub.rejectFix(projectID: id)
                dismiss()
            }
        } else {
            Text("אין תיקון שממתין לבדיקה")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct FixReviewContent: View {
    let project: Project
    @ObservedObject var session: FixSession
    let onApprove: () -> Void
    let onReject: () -> Void

    private var stats: (files: Int, added: Int, removed: Int) {
        var files = 0, added = 0, removed = 0
        for line in session.diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git") { files += 1 }
            else if line.hasPrefix("+"), !line.hasPrefix("+++") { added += 1 }
            else if line.hasPrefix("-"), !line.hasPrefix("---") { removed += 1 }
        }
        return (files, added, removed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("תיקון ל-\(project.name)").font(.title3.bold())
                let s = stats
                Text("\(s.files) קבצים · ").foregroundColor(.secondary)
                    + Text("+\(s.added)").foregroundColor(.green)
                    + Text(" −\(s.removed)").foregroundColor(.red)
                Spacer()
                buildBadge
            }

            if session.buildPassed == false {
                Label("ה-build עדיין נכשל אחרי \(session.maxAttempts) ניסיונות. מומלץ לבטל, או לאשר ולתקן ידנית.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !session.summary.isEmpty {
                ScrollView {
                    Text(session.summary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if !session.newFiles.isEmpty {
                Text("קבצים חדשים: \(session.newFiles.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DiffView(diff: session.diff)

            HStack {
                Button("↩︎ בטל את השינויים", role: .destructive, action: onReject)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("✓ אשר והפעל מחדש", action: onApprove)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.diff.isEmpty)
            }
        }
        .padding(16)
        .rtl()
    }

    @ViewBuilder private var buildBadge: some View {
        switch session.buildPassed {
        case .some(true): Label("Build עבר", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .some(false): Label("Build נכשל", systemImage: "xmark.seal.fill").foregroundStyle(.red)
        case .none: Label("בלי build", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}

struct DiffView: View {
    let diff: String

    var body: some View {
        let lines = diff.isEmpty ? ["(Claude לא שינה קבצים)"] : diff.components(separatedBy: "\n")
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(foreground(line))
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line))
                }
            }
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .ltr()
    }

    private func foreground(_ line: String) -> Color {
        if line.hasPrefix("@@") { return .purple }
        if line.hasPrefix("diff ") || line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("index ") {
            return .secondary
        }
        return .primary
    }

    private func background(_ line: String) -> Color {
        if line.hasPrefix("+"), !line.hasPrefix("+++") { return .green.opacity(0.15) }
        if line.hasPrefix("-"), !line.hasPrefix("---") { return .red.opacity(0.15) }
        return .clear
    }
}
