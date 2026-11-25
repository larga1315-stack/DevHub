import Foundation
import Combine
import DevHubCore

/// App-wide state: projects, runners, fix sessions, history, ports and settings.
@MainActor
final class Hub: ObservableObject {
    let store = ProjectStore()
    let history = CrashHistory()
    let settingsStore = SettingsStore()

    @Published private(set) var runners: [UUID: ProjectRunner] = [:]
    @Published private(set) var fixes: [UUID: FixSession] = [:]

    // Ports & processes
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var portOwners: [Int32: UUID] = [:]
    @Published private(set) var usage: [UUID: ProcessUsage] = [:]
    @Published private(set) var portsLoading = false
    /// The ports tab is on screen — only then do we run lsof.
    @Published var portsVisible = false {
        didSet { if portsVisible && !oldValue { Task { await refreshPorts() } } }
    }

    // Window routing
    @Published var editing: Project?
    @Published var logsProjectID: UUID?
    @Published var reviewProjectID: UUID?
    @Published var historyProjectID: UUID?
    @Published var notice: String?

    private var bag = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?
    private var cwdCache: [Int32: String] = [:]

    init() {
        for publisher in [store.objectWillChange, history.objectWillChange, settingsStore.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
        // One runner per project, always in sync with the store.
        store.$projects
            .sink { [weak self] projects in
                guard let self else { return }
                for project in projects where self.runners[project.id] == nil {
                    self.makeRunner(for: project)
                }
            }
            .store(in: &bag)
        settingsStore.$settings
            .sink { [weak self] settings in
                self?.runners.values.forEach { $0.usePTY = settings.usePTY }
            }
            .store(in: &bag)
        startPolling()
    }

    var settings: AppSettings { settingsStore.settings }
    var projects: [Project] { store.projects }
    var hasCrash: Bool { runners.values.contains { $0.crash != nil } }
    var anyRunning: Bool { runners.values.contains { $0.isRunning } }

    func runner(for id: UUID) -> ProjectRunner? { runners[id] }

    // MARK: - Projects

    func save(_ project: Project) {
        store.upsert(project)                    // creates the runner via the $projects sink
        runners[project.id]?.update(project: project)
        objectWillChange.send()
    }

    func delete(_ id: UUID) {
        runners[id]?.stop()
        runners[id] = nil
        fixes[id]?.cancel()
        fixes[id] = nil
        store.remove(id)
    }

    func stopAll() {
        runners.values.forEach { $0.stop() }
    }

    private func makeRunner(for project: Project) {
        let runner = ProjectRunner(project: project)
        runner.usePTY = settings.usePTY
        runner.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        runner.onCrash = { [weak self] report in
            guard let self else { return }
            self.history.add(CrashRecord(report: report), projectID: project.id)
            if self.settings.notifyOnCrash {
                let name = self.store.project(project.id)?.name ?? project.name
                Notifier.send(title: "\(name) קרס", body: Redactor.redact(report.triggerLine))
            }
        }
        runners[project.id] = runner
    }

    // MARK: - Ports & usage polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let seconds = UInt64(self.settings.portRefreshSeconds)
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
    }

    private func tick() async {
        guard portsVisible || anyRunning else {
            if !usage.isEmpty { usage = [:] }
            return
        }
        let entries = await ProcessStats.snapshot()

        // CPU / RAM per running project.
        var newUsage: [UUID: ProcessUsage] = [:]
        var trees: [UUID: Set<Int32>] = [:]
        for (id, runner) in runners {
            guard runner.isRunning, let pid = runner.pid else { continue }
            newUsage[id] = ProcessStats.usage(ofTree: pid, in: entries)
            trees[id] = ProcessStats.descendants(of: pid, in: entries)
        }
        usage = newUsage

        if portsVisible { await refreshPorts(trees: trees) }
    }

    func refreshPorts() async {
        let entries = await ProcessStats.snapshot()
        var trees: [UUID: Set<Int32>] = [:]
        for (id, runner) in runners {
            if runner.isRunning, let pid = runner.pid {
                trees[id] = ProcessStats.descendants(of: pid, in: entries)
            }
        }
        await refreshPorts(trees: trees)
    }

    private func refreshPorts(trees: [UUID: Set<Int32>]) async {
        portsLoading = true
        let scanned = await PortScanner.scan()

        // Which project owns each port: started by DevHub, or running from inside a project folder.
        var owners: [Int32: UUID] = [:]
        for port in scanned {
            if let id = trees.first(where: { $0.value.contains(port.pid) })?.key {
                owners[port.pid] = id
                continue
            }
            let cwd: String?
            if let cached = cwdCache[port.pid] {
                cwd = cached
            } else {
                cwd = await PortScanner.workingDirectory(of: port.pid)
                if let cwd { cwdCache[port.pid] = cwd }
            }
            if let cwd, let project = projects.first(where: { cwd == $0.path || cwd.hasPrefix($0.path + "/") }) {
                owners[port.pid] = project.id
            }
        }
        // Forget PIDs that are gone.
        let live = Set(scanned.map(\.pid))
        cwdCache = cwdCache.filter { live.contains($0.key) }

        ports = scanned
        portOwners = owners
        portsLoading = false
    }

    func stopProcess(_ port: ListeningPort, force: Bool = false) {
        do {
            try ProcessControl.terminate(pid: port.pid, owner: port.user, force: force)
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await refreshPorts()
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: - Fix flow

    func startFix(projectID: UUID) {
        guard fixes[projectID]?.phase.isBusy != true,
              let project = store.project(projectID),
              let crash = runners[projectID]?.crash else { return }

        let session = FixSession(projectID: projectID, crashID: crash.id)
        fixes[projectID] = session

        Task {
            let newSession = await session.run(project: project, crash: crash, settings: settings)
            if var current = store.project(projectID), current.claudeSessionID != newSession {
                current.claudeSessionID = newSession
                store.upsert(current)
                runners[projectID]?.update(project: current)
            }
            switch session.phase {
            case .review:
                reviewProjectID = projectID
                if settings.notifyOnFixReady {
                    let build = session.buildPassed == false ? " (ה-build עדיין נכשל)" : ""
                    Notifier.send(title: "התיקון ל-\(project.name) מוכן", body: "פתח את DevHub כדי לבדוק ולאשר\(build)")
                }
            case .failed(let message, _):
                history.update(crash.id, projectID: projectID, outcome: .failed)
                if settings.notifyOnFixReady {
                    Notifier.send(title: "התיקון ל-\(project.name) נכשל", body: message)
                }
            case .cancelled:
                history.update(crash.id, projectID: projectID, outcome: .cancelled)
            default:
                break
            }
        }
    }

    func cancelFix(projectID: UUID) {
        fixes[projectID]?.cancel()
    }

    /// Initializes git for the project, then retries the fix automatically.
    func initializeGitAndRetry(projectID: UUID) {
        guard let project = store.project(projectID) else { return }
        Task {
            do {
                if let note = try await Git.initialize(in: project.path) { notice = note }
                fixes[projectID] = nil
                startFix(projectID: projectID)
            } catch let error as GitError {
                notice = [error.localizedDescription, error.details].compactMap { $0 }.joined(separator: "\n")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    /// Keep Claude's change and relaunch the app.
    func approveFix(projectID: UUID) {
        if let session = fixes[projectID] {
            history.update(session.crashID, projectID: projectID, outcome: .approved, summary: session.summary)
        }
        fixes[projectID] = nil
        runners[projectID]?.clearCrash()
        runners[projectID]?.restart()
        if reviewProjectID == projectID { reviewProjectID = nil }
    }

    /// Throw away Claude's change and restore the snapshot.
    func rejectFix(projectID: UUID) {
        guard let session = fixes[projectID], let project = store.project(projectID) else { return }
        Task {
            do {
                try await session.revert(project: project)
                history.update(session.crashID, projectID: projectID, outcome: .rejected, summary: session.summary)
                let leftovers = session.newFiles
                notice = leftovers.isEmpty
                    ? "השינויים בוטלו והקוד חזר למצב שלפני התיקון."
                    : "השינויים בוטלו. קבצים חדשים שנוצרו לא נמחקו: \(leftovers.joined(separator: ", "))"
                fixes[projectID] = nil
                if reviewProjectID == projectID { reviewProjectID = nil }
            } catch let error as GitError {
                notice = [error.localizedDescription, error.details].compactMap { $0 }.joined(separator: "\n")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    func dismissFix(projectID: UUID) {
        fixes[projectID] = nil
    }
}
