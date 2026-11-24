// Checks iCloud save sync (ios/RetroDuo/SaveSync.swift) with a local folder standing in for iCloud.
//   swiftc SaveSync.swift tests/savesync/main.swift -o savesync_test && ./savesync_test
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print((condition ? "ok   " : "FAIL ") + message)
    if !condition { failures += 1 }
}

let now = Date()
let plan = SaveSyncPlan.plan(local: ["a.sav": now, "b.sav": now.addingTimeInterval(-100), "c.sav": now, "same.sav": now],
                             cloud: ["b.sav": now, "c.sav": now.addingTimeInterval(-100), "d.sav": now, "same.sav": now.addingTimeInterval(1)])
check(plan.upload == ["a.sav", "c.sav"], "uploads what iCloud lacks or has older")
check(plan.download == ["b.sav", "d.sav"], "downloads what this device lacks or has older")
check(!plan.upload.contains("same.sav") && !plan.download.contains("same.sav"), "copies a second apart count as the same")
check(SaveSyncPlan.syncable("Pokemon Red.sav") && SaveSyncPlan.syncable("Zelda.quick.state") && SaveSyncPlan.syncable("Zelda.quick.preview.png"),
      "saves, states and previews are synced")
check(!SaveSyncPlan.syncable(".DS_Store") && !SaveSyncPlan.syncable("x.sav.tmp") && !SaveSyncPlan.syncable("game.gba"),
      "hidden files, temporary files and games aren't")

// Two "devices" sharing one stand-in iCloud folder.
let root = FileManager.default.temporaryDirectory.appendingPathComponent("savesync-\(UUID().uuidString)")
let cloud = root.appendingPathComponent("cloud")
func device(_ name: String) -> (saves: URL, states: URL, engine: SaveSyncEngine) {
    let saves = root.appendingPathComponent("\(name)/Saves"), states = root.appendingPathComponent("\(name)/States")
    return (saves, states, SaveSyncEngine(folders: [(saves, "Saves"), (states, "States")]))
}
func write(_ text: String, _ url: URL, age: TimeInterval) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(text.utf8).write(to: url)
    try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
}
func read(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

let phone = device("phone"), tablet = device("tablet")
write("red: 3 badges", phone.saves.appendingPathComponent("Pokemon Red.sav"), age: 600)
write("quick state", phone.states.appendingPathComponent("Pokemon Red.quick.state"), age: 600)
write("ignore me", phone.saves.appendingPathComponent(".DS_Store"), age: 600)
var result = phone.engine.run(container: cloud)
check(result.uploaded == 2 && result.downloaded == 0, "the first device uploads its saves (\(result.uploaded) up)")
check(read(cloud.appendingPathComponent("Documents/Saves/Pokemon Red.sav")) == "red: 3 badges", "the save is in iCloud")
check(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("Documents/Saves/.DS_Store").path), "hidden files stay behind")

result = tablet.engine.run(container: cloud)
check(result.downloaded == 2, "a second device downloads them (\(result.downloaded) down)")
check(read(tablet.saves.appendingPathComponent("Pokemon Red.sav")) == "red: 3 badges", "with the same contents")
result = tablet.engine.run(container: cloud)
check(result.uploaded == 0 && result.downloaded == 0, "syncing again changes nothing (dates are kept)")

write("red: 4 badges", tablet.saves.appendingPathComponent("Pokemon Red.sav"), age: 10)
_ = tablet.engine.run(container: cloud)
result = phone.engine.run(container: cloud)
check(result.downloaded == 1 && read(phone.saves.appendingPathComponent("Pokemon Red.sav")) == "red: 4 badges",
      "newer progress on one device reaches the other")

write("red: old copy", phone.saves.appendingPathComponent("Pokemon Red.sav"), age: 5000)
result = phone.engine.run(container: cloud)
check(result.downloaded == 1 && read(phone.saves.appendingPathComponent("Pokemon Red.sav")) == "red: 4 badges",
      "an older local copy never overwrites newer progress in iCloud")

try? FileManager.default.removeItem(at: tablet.saves.appendingPathComponent("Pokemon Red.sav"))
_ = tablet.engine.run(container: cloud)
check(FileManager.default.fileExists(atPath: cloud.appendingPathComponent("Documents/Saves/Pokemon Red.sav").path),
      "deleting a save on one device doesn't delete it from iCloud")
check(read(tablet.saves.appendingPathComponent("Pokemon Red.sav")) == "red: 4 badges", "and it comes back")

try? FileManager.default.removeItem(at: root)
print(failures == 0 ? "\nall save sync checks passed" : "\n\(failures) save sync check(s) failed")
exit(failures == 0 ? 0 : 1)
