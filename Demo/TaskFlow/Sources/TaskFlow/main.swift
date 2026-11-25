import TaskFlowCore

let manifest = """
# name      duration  priority  deps
fetch       12s       5         -
assets      500ms     1         fetch
compile     2m        9         fetch
test        1m30s     7         compile
sign        3s        3         compile
package     45s       5         compile, assets, sign
release     0s        0         package, test
lint        20s       2         -
codegen     30s       4         checks
typecheck   1m        6         codegen
checks      0s        0         lint, typecheck
all         0s        0         release, checks
"""

print("TaskFlow: loading manifest…")
let tasks = try ManifestParser.parse(manifest)
let scheduler = Scheduler(tasks)

for target in ["release", "all"] {
    print("Planning target '\(target)'…")
    let order = scheduler.plan(target)
    print("  order: \(order.joined(separator: " → "))")
    print("  2 workers: \(scheduler.makespan(target, workers: 2))s")
}

print("Cache keys:")
for task in tasks {
    print("  \(task.name): \(Fingerprint.hex(task.signature))")
}
print("✓ done")
