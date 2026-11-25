import SwiftUI
import DevHubCore

struct HistoryWindow: View {
    @EnvironmentObject private var hub: Hub

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("פרויקט", selection: $hub.historyProjectID) {
                    ForEach(hub.projects) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                .frame(maxWidth: 280)
                Spacer()
                if let id = hub.historyProjectID, !hub.history.records(for: id).isEmpty {
                    Button("נקה היסטוריה") { hub.history.clear(projectID: id) }
                }
            }
            .padding(10)

            Divider()

            if let id = hub.historyProjectID {
                let records = hub.history.records(for: id)
                if records.isEmpty {
                    Text("אין קריסות שנרשמו לפרויקט הזה")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(records) { record in
                        HistoryRow(record: record)
                    }
                }
            } else {
                Text("בחר פרויקט").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .rtl()
        .onAppear { if let id = hub.historyProjectID { hub.history.preload(id) } }
        .onChange(of: hub.historyProjectID) { _, id in if let id { hub.history.preload(id) } }
    }
}

struct HistoryRow: View {
    let record: CrashRecord
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.outcome.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.18), in: Capsule())
                    .foregroundStyle(color)
                Text(record.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(record.triggerLine)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(expanded ? nil : 2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ltr()
            if !record.fileRefs.isEmpty {
                Text(record.fileRefs.joined(separator: "  ·  "))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .ltr()
            }
            if let summary = record.summary, !summary.isEmpty {
                DisclosureGroup("מה Claude עשה", isExpanded: $expanded) {
                    Text(summary)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch record.outcome {
        case .approved: return .green
        case .rejected, .cancelled: return .gray
        case .failed: return .red
        case .open: return .orange
        }
    }
}
