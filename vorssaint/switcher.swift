// Gives the Vorssaint radial-menu mouse trigger to a per-app profile while that app is frontmost.
// Vorssaint allows one wheel per mouse button, so we move `mouseButton` between profiles
// inside the `radialMenuProfiles` JSON blob in its preferences. Profiles are matched by name.
//   switcher watch <config.json>                 follow the frontmost app
//   switcher apply <config.json> [profile name]  one-off (default profile when omitted)
//   switcher setup <config.json> <scripts dir>   create/refresh the Teams profile (backs up first)
import AppKit

struct Config: Decodable {
    let domain: String
    let trigger: String
    let defaultProfile: String   // name of the profile used when no app rule matches; first profile if not found
    let apps: [String: String]   // bundle id -> profile name
}

let args = CommandLine.arguments
guard args.count >= 3,
      let data = FileManager.default.contents(atPath: args[2]),
      let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
    FileHandle.standardError.write(Data("usage: switcher watch|apply|setup <config.json> [arg]\n".utf8))
    exit(2)
}
let key = "radialMenuProfiles" as CFString
let domain = cfg.domain as CFString

func load() -> [[String: Any]]? {
    CFPreferencesAppSynchronize(domain)
    guard let blob = CFPreferencesCopyAppValue(key, domain) as? Data else { return nil }
    return (try? JSONSerialization.jsonObject(with: blob)) as? [[String: Any]]
}

func save(_ profiles: [[String: Any]]) {
    guard let out = try? JSONSerialization.data(withJSONObject: profiles) else { return }
    CFPreferencesSetAppValue(key, out as CFData, domain)
    CFPreferencesAppSynchronize(domain)
}

func apply(profileNamed name: String?) {
    guard var profiles = load(), !profiles.isEmpty else {
        FileHandle.standardError.write(Data("no Vorssaint radial profiles found\n".utf8))
        return
    }
    let wanted = name ?? cfg.defaultProfile
    let index = profiles.firstIndex { $0["name"] as? String == wanted }
        ?? profiles.firstIndex { $0["name"] as? String == cfg.defaultProfile } ?? 0
    var changed = false
    for i in profiles.indices {
        let want = i == index ? cfg.trigger : "off"
        if profiles[i]["mouseButton"] as? String != want {
            profiles[i]["mouseButton"] = want
            changed = true
        }
    }
    if changed {
        save(profiles)
        print("active profile -> \(profiles[index]["name"] as? String ?? "")")
    }
}

func setup(scriptsDir: String) {
    guard let teamsName = cfg.apps["com.microsoft.teams2"] ?? cfg.apps.values.first else { return }
    var profiles = load() ?? []
    // Backup first.
    let backupDir = NSString(string: "~/.config/vorssaint-profiles").expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
    if let old = try? JSONSerialization.data(withJSONObject: profiles) {
        let stamp = Int(Date().timeIntervalSince1970)
        FileManager.default.createFile(atPath: "\(backupDir)/radialMenuProfiles-\(stamp).json", contents: old)
    }
    let slices: [(file: String, name: String, symbol: String)] = [
        ("teams-react-like.sh", "Like", "hand.thumbsup.fill"),
        ("teams-react-love.sh", "Love", "heart.fill"),
        ("teams-react-applause.sh", "Applause", "hands.clap.fill"),
        ("teams-react-laugh.sh", "Laugh", "face.smiling.fill"),
        ("teams-react-wow.sh", "Wow", "sparkles"),
        ("teams-hand-toggle.sh", "Hand", "hand.raised.fill"),
        ("teams-mute.sh", "Mute", "mic.fill"),
        ("teams-camera.sh", "Camera", "video.fill"),
        ("teams-share.sh", "Share", "square.and.arrow.up"),
        ("teams-chat.sh", "Chat", "bubble.left.fill"),
        ("teams-people.sh", "People", "person.2.fill"),
    ]
    let items: [[String: Any]] = slices.map {
        ["id": UUID().uuidString, "payload": "\(scriptsDir)/\($0.file)", "children": [] as [Any],
         "kind": "file", "name": $0.name, "symbolName": $0.symbol]
    }
    if let i = profiles.firstIndex(where: { $0["name"] as? String == teamsName }) {
        profiles[i]["items"] = items
    } else {
        profiles.append(["id": UUID().uuidString, "preset": "general", "shortcut": "", "name": teamsName,
                         "color": "indigo", "items": items, "trackpadTap": false, "mouseButton": "off"])
    }
    save(profiles)
    print("profile '\(teamsName)' set up with \(items.count) slices; backup in \(backupDir)")
}

switch args[1] {
case "apply":
    apply(profileNamed: args.count > 3 ? args[3] : nil)
case "setup":
    guard args.count > 3 else { exit(2) }
    setup(scriptsDir: args[3])
case "watch":
    func current(_ id: String?) -> String? { id.flatMap { cfg.apps[$0] } }
    apply(profileNamed: current(NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        // Ignore Vorssaint/Raycast popping up so the wheel stays put while you use it.
        if let id = app?.bundleIdentifier, id == "com.vorssaint.utils" || id == "com.raycast.macos" { return }
        apply(profileNamed: current(app?.bundleIdentifier))
    }
    RunLoop.main.run()
default:
    exit(2)
}
