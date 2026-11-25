import Foundation

// A deliberately broken app for testing DevHub's crash → Claude Code → fix flow.

struct User {
    let id: Int
    let name: String
}

let users = [1: User(id: 1, name: "Hezy")]

func loadUser(id: Int) -> User? {
    users[id]
}

/// Used in two places — a good fix must keep both working.
func greeting(for id: Int) -> String {
    let user = loadUser(id: id)!          // 💥 crashes when the user doesn't exist
    return "שלום \(user.name)"
}

func profileTitle(for id: Int) -> String {
    "פרופיל: " + greeting(for: id)
}

print("CrashDemo starting…")
print(greeting(for: 1))
print(profileTitle(for: 1))
Thread.sleep(forTimeInterval: 1)
print(greeting(for: 2))                   // user 2 doesn't exist
print("done")
