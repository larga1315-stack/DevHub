# DevHub

> **English summary:** DevHub is a macOS menu-bar developer control center. It runs your projects, catches crashes, and fixes them with Claude Code in one click: a git snapshot first, Claude restricted to file tools inside the project (no shell, no network), automatic build and test verification, then a diff you approve or roll back. It also shows listening ports (with one-click stop) and CPU/RAM per project. Swift 5.9 · SwiftUI · macOS 14+ · MIT.

מרכז שליטה למפתחים ב-macOS, שיושב ב-menu bar. מריץ את הפרויקטים שלך, תופס קריסות, ומתקן אותן עם Claude Code בלחיצה. לפני כל תיקון נשמרת נקודת שחזור, וכל שינוי מחכה לאישור שלך.

```
crash בלוג → נקודת שחזור ב-git → Claude Code מתקן (רק בתיקיית הפרויקט, בלי shell ובלי רשת)
          → build אוטומטי (עד 2 ניסיונות) → diff לאישור → הפעלה מחדש / ביטול
```

## יכולות
- **הרצת פרויקטים:** Swift Package, Xcode (macOS), Node. לוגים חיים עם סינון וחיפוש.
- **זיהוי קריסות:** Swift fatal errors, חריגות Objective-C, signals, Python, Node, Go. הפרויקטים רצים בתוך terminal וירטואלי, כך שפלט שהודפס רגע לפני קריסה לא הולך לאיבוד, ועם backtrace של Swift שמראה בדיוק איפה הקוד קרס.
- **תיקון עם Claude Code**, עם ניתוח הקבצים שמוזכרים בקריסה, סשן נפרד לכל פרויקט, ואפשרות לעצור באמצע.
- **נקודת שחזור לפני כל תיקון**, diff צבעוני לאישור, וביטול בלחיצה.
- **זיהוי אוטומטי של סוג הפרויקט**, התיקייה הראשית וה-schemes של Xcode.
- **אתחול git מובנה**, עם ‎.gitignore‎ שמחריג קבצי build וסודות.
- **היסטוריית קריסות** לכל פרויקט, נשמרת אחרי שהטקסט עבר הסתרת סודות.
- **פורטים:** כל הפורטים הפתוחים, מי תופס אותם, ולאיזה פרויקט הם שייכים. עצירה בלחיצה, פתיחה בדפדפן, ואזהרה על שרת שפתוח לרשת.
- **CPU ו-RAM** לכל פרויקט רץ, כולל תהליכי משנה.
- **התראות macOS** על קריסה ועל תיקון מוכן, **הפעלה עם הפעלת המחשב**, ומסך הגדרות.

## דרישות
- macOS 14 ומעלה, Xcode 15 ומעלה (או Swift 5.9 ומעלה)
- [Claude Code](https://docs.claude.com/en/docs/claude-code) מותקן ומחובר (הפקודה `claude` עובדת בטרמינל)

## התקנה
```bash
git clone <repo-url> DevHub && cd DevHub
./scripts/build-app.sh --install
```
הסקריפט בונה `DevHub.app`, מתקין אותה ב-`/Applications` ומפעיל אותה.

**לפיתוח:** `open Package.swift` ב-Xcode ואז ▶︎, או `swift run`.

## טסטים
```bash
swift test
```
יש 59 טסטים על הליבה: זיהוי קריסות, חילוץ קבצים (כולל הגנה מ-path traversal), הסתרת סודות, git snapshot/restore, זיהוי פרויקטים, פירוק פלט lsof ו-ps, הגנות על עצירת תהליכים, הגדרות, ובניית הפרומפט וההרשאות של Claude. ה-CI מריץ אותם על כל push.

## הגדרת פרויקט
לוחצים **+ פרויקט** ובוחרים תיקייה. DevHub מזהה לבד את סוג הפרויקט ואת הפקודות. אם בחרת תיקייה פנימית, הוא יציע את התיקייה הראשית.

פקודת ההרצה **חייבת להישאר בחזית**, אחרת DevHub לא רואה את הלוגים:

| סוג | פקודת הרצה |
|---|---|
| Swift Package | `swift run` |
| macOS (Xcode) | ‎`xcodebuild … build && ./.devhub-build/Build/Products/Debug/App.app/Contents/MacOS/App`‎ (מתמלא לבד) |
| iOS בסימולטור | `xcrun simctl launch --console-pty booted com.your.bundle.id` |
| Node | `npm run dev` |

לא להריץ עם `open App.app`, כי ככה הלוגים לא מגיעים ל-DevHub.

## אבטחה
| סיכון | מזהה | טיפול |
|---|---|---|
| סוכן AI עם הרשאות רחבות מדי | OWASP LLM06:2025, CWE-250 | Claude מקבל רק `Read, Edit, Write, Grep, Glob`. `Bash`, `WebFetch` ו-`WebSearch` חסומים, ויש לכל היותר 30 צעדים. את ה-build מריץ DevHub ולא Claude |
| Prompt injection דרך הלוג | OWASP LLM01:2025 | הלוג עטוף ב-`<runtime_log>` עם הוראה להתייחס אליו כנתונים בלבד. ההגבלה של הכלים מצמצמת את הנזק גם אם הזרקה מצליחה |
| דליפת סודות לענן או לדיסק | CWE-532, CWE-200 | הסתרה של מפתחות API, JWT, טוקנים, סיסמאות ומפתחות פרטיים לפני שליחה ל-Claude ולפני שמירה בהיסטוריה |
| commit של סודות באתחול git | CWE-312 | ה-‎.gitignore‎ שנוצר מחריג ‎.env‎, ‎*.pem‎, ‎*.p12‎, ‎*.key‎. יש לזה טסט |
| הזרקת פקודות OS | CWE-78 | פרומפטים ולוגים עוברים רק כ-arguments array, אף פעם לא דרך shell |
| קבצים מחוץ לפרויקט | CWE-22 | רק קבצים שנמצאים בפועל בתוך תיקיית הפרויקט נכנסים לפרומפט. יש לזה טסט |
| עצירת תהליך לא נכון | CWE-250 | עצירה רק לתהליכים של המשתמש הנוכחי, אף פעם לא ל-PID נמוך מ-100 או ל-DevHub עצמו, ותמיד עם אישור. יש לזה טסט |
| שרת פיתוח חשוף לרשת | CWE-668 | אזהרה בולטת על פורט שמאזין על כל הממשקים |
| הזרקה דרך שדה "מודל" | CWE-88 | שם המודל מסונן לתווים מותרים לפני שהוא עובר כ-argument |

מקורות: OWASP Top 10 for LLM Applications 2025, MITRE CWE.

## מבנה
```
Sources/
├── DevHubCore/            ← כל הלוגיקה, בלי UI, עם טסטים
│   ├── Models.swift           Project, ProjectStore, AppPaths
│   ├── ProjectRunner.swift    הרצה, סטרים של לוגים, זיהוי קריסה
│   ├── CrashDetector.swift    תבניות, file:line, Redactor
│   ├── ProjectDetector.swift  תיקייה ראשית, סוג, פקודות, schemes
│   ├── Git.swift              state / initialize / snapshot / diff / restore
│   ├── FixSession.swift       הזרימה מול Claude Code + פרומפטים
│   ├── CrashHistory.swift     היסטוריה לכל פרויקט
│   ├── Ports.swift            סריקת פורטים, עצירת תהליכים, CPU/RAM
│   ├── Settings.swift         הגדרות + שמירה
│   └── Shell.swift            הרצת תהליכים, ביטול, PATH
└── DevHub/                ← אפליקציית SwiftUI
    ├── DevHubApp.swift, Hub.swift, System.swift (התראות, login item)
    └── Views/  MenuPanel · PortsView · ProjectEditor · LogsWindow · FixReviewWindow · HistoryWindow · SettingsWindow
Tests/DevHubCoreTests/
scripts/build-app.sh
.github/workflows/ci.yml
Demo/CrashDemo/            ← אפליקציה שקורסת בכוונה, לבדיקה
```

## פרויקטי דמו
בתיקייה `Demo/` יש שלוש אפליקציות שבורות בכוונה, לבדיקת זרימת התיקון:

| דמו | קושי | מה שבור |
|---|---|---|
| `CrashDemo` | קל | force unwrap של nil |
| `ShopDemo` | בינוני | 4 באגים בשרשרת: פירוק CSV, מחירים עשרוניים, `\r\n`, חריגה מגבולות מערך. 9 טסטים |
| `TaskFlow` | קשה | stack overflow ממעגל תלויות חבוי, integer overflow שקט, תוצאות שגויות וסדר אקראי. 15 טסטים |

כדי להשתמש: מעתיקים את הדמו לתיקייה נפרדת, מריצים `git init && git add . && git commit -m init`, ומוסיפים אותו ל-DevHub.

## מגבלות ידועות
- נקודת השחזור מכסה קבצים במעקב git. קבצים חדשים ש-Claude יצר מוצגים, אבל לא נמחקים אוטומטית.
- זיהוי הקריסה מבוסס על תבניות טקסט ועל קוד יציאה.
- הסתרת הסודות מבוססת regex: שכבת הגנה, לא ערובה.
- ה-`.app` חתום ad-hoc ולא עבר notarization. במחשב אחר macOS יציג אזהרה בפתיחה הראשונה (System Settings → Privacy & Security → Open Anyway).
- שכבת ה-UI (SwiftUI) לא מכוסה בטסטים. כל הלוגיקה נמצאת ב-`DevHubCore` ונבדקת שם.

## אבטחה ודיווח על חולשות
ראו [SECURITY.md](SECURITY.md).

## רישיון
MIT. ראו [LICENSE](LICENSE).

## Roadmap
- [x] שלב 1: יסודות (מבנה מודולרי, טסטים, CI, ‎.app‎, אתחול git, זיהוי תיקייה, היסטוריה)
- [x] שלב 2: פורטים ותהליכים, CPU/RAM, מסך הגדרות, התראות, הפעלה עם הפעלת המחשב
- [ ] שלב 3: מעקב מכסות Claude Code ו-Codex, הסבר מהיר עם Ollama מקומי
- [ ] שלב 4: אייקון, צילומי מסך, Release ב-GitHub עם notarization
