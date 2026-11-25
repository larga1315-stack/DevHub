import SwiftUI
import AppKit
import DevHubCore

struct SettingsWindow: View {
    @EnvironmentObject private var hub: Hub
    @State private var detectedClaude: String?
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginError: String?

    private var settings: Binding<AppSettings> {
        Binding(get: { hub.settingsStore.settings }, set: { hub.settingsStore.settings = $0 })
    }

    var body: some View {
        Form {
            Section("Claude Code") {
                TextField("נתיב ל-claude", text: settings.claudePath,
                          prompt: Text(detectedClaude ?? "אוטומטי"))
                    .ltr()
                if settings.wrappedValue.claudePath.isEmpty {
                    Text(detectedClaude.map { "נמצא אוטומטית: \($0)" } ?? "לא נמצא. התקן את Claude Code או הזן נתיב.")
                        .font(.caption)
                        .foregroundStyle(detectedClaude == nil ? Color.red : Color.secondary)
                } else if !FileManager.default.isExecutableFile(atPath: settings.wrappedValue.claudePath) {
                    Text("הנתיב לא קיים או לא ניתן להרצה. DevHub יחפש אוטומטית.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                TextField("מודל", text: settings.model, prompt: Text("ברירת מחדל"))
                    .ltr()

                Stepper(value: settings.maxAttempts, in: AppSettings.attemptsRange) {
                    Text("ניסיונות תיקון אחרי build שנכשל: \(settings.wrappedValue.maxAttempts)")
                }
                Stepper(value: settings.maxTurns, in: AppSettings.turnsRange, step: 5) {
                    Text("מקסימום צעדים ל-Claude בכל ניסיון: \(settings.wrappedValue.maxTurns)")
                }
                Text("Claude מקבל רק קריאה ועריכה של קבצים בתוך הפרויקט. אין לו גישה ל-shell או לרשת.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("התראות") {
                Toggle("כשפרויקט קורס", isOn: settings.notifyOnCrash)
                Toggle("כשתיקון מוכן או נכשל", isOn: settings.notifyOnFixReady)
                if !isAppBundle {
                    Text("התראות עובדות רק מהאפליקציה המותקנת, לא מ-Xcode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("כללי") {
                Toggle("הפעל עם הפעלת המחשב", isOn: $loginEnabled)
                    .disabled(!LoginItem.isSupported)
                    .onChange(of: loginEnabled) { _, newValue in
                        guard newValue != LoginItem.isEnabled else { return }
                        do {
                            try LoginItem.set(newValue)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            loginEnabled = LoginItem.isEnabled
                        }
                    }
                if LoginItem.isSupported {
                    Text(loginError ?? LoginItem.statusText)
                        .font(.caption)
                        .foregroundStyle(loginError == nil ? Color.secondary : Color.red)
                } else {
                    Text("זמין רק מהאפליקציה המותקנת.").font(.caption).foregroundStyle(.secondary)
                }

                Toggle("הרץ פרויקטים בתוך terminal וירטואלי (מומלץ)", isOn: settings.usePTY)
                Text("שומר את מה שהאפליקציה הדפיסה רגע לפני קריסה. בלי זה הפלט עלול ללכת לאיבוד.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper(value: settings.portRefreshSeconds, in: 1...60) {
                    Text("רענון פורטים ותהליכים כל \(settings.wrappedValue.portRefreshSeconds) שניות")
                }
            }

            Section("נתונים") {
                HStack {
                    Text("פרויקטים, היסטוריה והגדרות נשמרים מקומית בלבד.")
                        .font(.caption)
                    Spacer()
                    Button("פתח תיקייה") { NSWorkspace.shared.open(AppPaths.supportDirectory) }
                }
                Text(verbatim: "DevHub \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .rtl()
        .task {
            detectedClaude = await Shell.findClaude()
            loginEnabled = LoginItem.isEnabled
        }
    }
}
