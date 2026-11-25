import SwiftUI
import AppKit
import DevHubCore

struct LogsWindow: View {
    @EnvironmentObject private var hub: Hub
    @State private var filter = ""
    @State private var errorsOnly = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("פרויקט", selection: $hub.logsProjectID) {
                    ForEach(hub.projects) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                .frame(maxWidth: 260)

                TextField("סינון…", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Toggle("רק שגיאות", isOn: $errorsOnly)
                    .toggleStyle(.checkbox)

                Spacer()

                if let id = hub.logsProjectID, let runner = hub.runner(for: id) {
                    Button {
                        let text = runner.logs.map(\.text).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .help("העתק את כל הלוג")

                    Button { runner.clearLogs() } label: { Image(systemName: "trash") }
                        .help("נקה")
                }
            }
            .padding(10)
            .rtl()

            Divider()

            if let id = hub.logsProjectID, let runner = hub.runner(for: id) {
                LogList(runner: runner, filter: filter, errorsOnly: errorsOnly)
            } else {
                Text("בחר פרויקט").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct LogList: View {
    @ObservedObject var runner: ProjectRunner
    let filter: String
    let errorsOnly: Bool

    private var visible: [LogLine] {
        runner.logs.filter { line in
            (!errorsOnly || line.isError || CrashDetector.isCrashLine(line.text))
                && (filter.isEmpty || line.text.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        let lines = visible
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: runner.logs.count) { _, _ in
                if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .ltr()
    }

    private func color(for line: LogLine) -> Color {
        if CrashDetector.isCrashLine(line.text) { return .red }
        return line.isError ? .orange : .primary
    }
}
