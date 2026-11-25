import SwiftUI
import AppKit
import DevHubCore

struct ProjectEditor: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.dismiss) private var dismiss

    @State private var draft = Project()
    @State private var suggestedRoot: String?
    @State private var gitState: GitState?
    @State private var schemes: [String] = []
    @State private var scheme = ""
    @State private var lastAuto: DetectedProject?
    @State private var initializingGit = false
    @State private var gitError: String?

    private var isExisting: Bool { hub.projects.contains { $0.id == draft.id } }
    private var pathExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: draft.path, isDirectory: &isDir) && isDir.boolValue
    }
    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && pathExists
            && !draft.runCommand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isExisting ? "הגדרות פרויקט" : "פרויקט חדש").font(.title3.bold())

            field("תיקיית הפרויקט") {
                HStack {
                    TextField("/Users/…/MyApp", text: $draft.path)
                        .ltr()
                    Button("בחר…") { pickFolder() }
                }
            }

            if let root = suggestedRoot {
                banner(icon: "arrow.up.forward.square", color: .orange) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("זו תיקייה פנימית. נראה שהפרויקט עצמו נמצא כאן:").font(.caption)
                        Text(root).font(.system(.caption, design: .monospaced)).ltr()
                    }
                    Spacer()
                    Button("השתמש בה") { apply(root: root) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            if pathExists { gitStatusRow }

            field("שם") { TextField("Jarvis", text: $draft.name) }

            if draft.kind == .xcode, schemes.count > 1 {
                field("Scheme") {
                    Picker("", selection: $scheme) {
                        ForEach(schemes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: scheme) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        refreshCommands(scheme: newValue, force: false)
                    }
                }
            }

            field("פקודת הרצה (חייבת להישאר בחזית כדי ש-DevHub יראה את הלוגים)") {
                TextField("swift run", text: $draft.runCommand, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                    .ltr()
            }

            field("פקודת build לבדיקת התיקון (מומלץ)") {
                TextField("swift build", text: $draft.buildCommand, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                    .ltr()
            }

            HStack {
                if isExisting {
                    Button("מחק פרויקט", role: .destructive) {
                        hub.delete(draft.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("ביטול") { dismiss() }
                Button("שמור") {
                    hub.save(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 580)
        .rtl()
        .onAppear { load(hub.editing) }
        .onChange(of: hub.editing) { _, newValue in load(newValue) }
        .onChange(of: draft.path) { _, _ in pathChanged() }
    }

    // MARK: - Git status

    @ViewBuilder private var gitStatusRow: some View {
        switch gitState {
        case .some(.ready):
            Label("git תקין: אפשר לתקן בבטחה", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .some(let state):
            banner(icon: "exclamationmark.triangle.fill", color: .yellow) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state == .notRepo ? "התיקייה לא ב-git." : "אין עדיין commit ב-repository.")
                        .font(.caption.bold())
                    Text("בלי זה אין נקודת שחזור לפני תיקון. אפשר לאתחל עכשיו או בזמן התיקון.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let gitError {
                        Text(gitError).font(.caption2).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Spacer()
                if initializingGit {
                    ProgressView().controlSize(.small)
                } else {
                    Button("אתחל git") { initGit() }.controlSize(.small)
                }
            }
        case .none:
            EmptyView()
        }
    }

    private func initGit() {
        initializingGit = true
        gitError = nil
        let path = draft.path
        Task {
            do {
                if let note = try await Git.initialize(in: path) { hub.notice = note }
            } catch let error as GitError {
                gitError = [error.localizedDescription, error.details].compactMap { $0 }.joined(separator: "\n")
            } catch {
                gitError = error.localizedDescription
            }
            gitState = await Git.state(in: path)
            initializingGit = false
        }
    }

    // MARK: - Detection

    private func load(_ project: Project?) {
        guard let project else { return }
        draft = project
        lastAuto = nil
        schemes = []
        scheme = ""
        pathChanged()
    }

    private func pathChanged() {
        let path = draft.path
        gitState = nil
        gitError = nil
        guard pathExists else { suggestedRoot = nil; return }

        let root = ProjectDetector.findRoot(from: path)
        suggestedRoot = (root != nil && root != URL(fileURLWithPath: path).standardizedFileURL.path) ? root : nil

        Task {
            let state = await Git.state(in: path)
            if draft.path == path { gitState = state }
        }
        if ProjectDetector.isProjectRoot(path) {
            refreshCommands(scheme: nil, force: false)
            loadSchemes(for: path)
        }
    }

    private func apply(root: String) {
        draft.path = root   // triggers pathChanged
        suggestedRoot = nil
    }

    /// Fills name/kind/commands. Never overwrites commands the user typed themselves.
    private func refreshCommands(scheme: String?, force: Bool) {
        let detected = ProjectDetector.detect(at: draft.path, scheme: scheme)
        let previousName = lastAuto?.name
        if draft.name.isEmpty || draft.name == previousName { draft.name = detected.name }
        draft.kind = detected.kind

        let runIsAuto = draft.runCommand.isEmpty || draft.runCommand == lastAuto?.runCommand
        let buildIsAuto = draft.buildCommand.isEmpty || draft.buildCommand == lastAuto?.buildCommand
        if force || runIsAuto { draft.runCommand = detected.runCommand }
        if force || buildIsAuto { draft.buildCommand = detected.buildCommand }
        lastAuto = detected
    }

    private func loadSchemes(for path: String) {
        guard ProjectDetector.detect(at: path).kind == .xcode else { return }
        Task {
            let found = await ProjectDetector.xcodeSchemes(at: path)
            guard draft.path == path else { return }
            schemes = found
            if let first = found.first, scheme.isEmpty {
                scheme = first
                refreshCommands(scheme: first, force: false)
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "בחר"
        panel.message = "בחר את התיקייה הראשית של הפרויקט (זו שיש בה Package.swift, ‎.xcodeproj‎ או ‎.git‎)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.path = url.path
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func banner<Content: View>(icon: String, color: Color,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            content()
        }
        .padding(8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
