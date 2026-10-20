// Presses Microsoft Teams meeting buttons by accessibility name, independent of window size/layout.
//   teams-ui like|love|applause|laugh|wow|hand|mute|camera|share|chat|people
// Window = the one that contains the "Reager"/"React" toolbar button (skips chat and shared-content windows).
import AppKit
import ApplicationServices

var reactions: [String: [String]] = [
    "like": ["Liker", "Like"],
    "love": ["Kjærlighet", "Love", "Heart"],
    "applause": ["Applaus", "Applause", "Clap"],
    "laugh": ["Ler", "Laugh"],
    "wow": ["Overrasket", "Surprised", "Wow"],
]
var reactButton = ["Reager", "React", "Reactions"]
let handButton = ["Hev", "Senk", "Raise", "Lower"]
// Toolbar buttons matched by label keywords (Norwegian + English); toggles keep their position, only the label flips.
var toolbar: [String: (any: [String], not: [String])] = [
    "hand": (["hev", "senk", "raise", "lower"], []),
    "mute": (["mikrofon", "microphone", "mute"], ["alternativer", "options"]),
    "camera": (["kamera", "camera", "video"], ["alternativer", "options"]),
    "share": (["dele", "share"], ["alternativer", "options"]),
    "chat": (["chat"], []),
    "people": (["personer", "people"], []),
]

// Other Teams UI languages: add labels in ~/.config/teams-ui/labels.json, e.g.
// {"react": ["Reagieren"], "like": ["Gefällt mir"], "mute": ["mikrofon"], "hand": ["hand"]}
// Use `teams-ui dump` during a meeting to list the labels Teams exposes.
func loadLabelOverrides() {
    let path = NSString(string: "~/.config/teams-ui/labels.json").expandingTildeInPath
    guard let data = FileManager.default.contents(atPath: path),
          let extra = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String]] else { return }
    for (k, v) in extra {
        if k == "react" { reactButton += v }
        else if reactions[k] != nil { reactions[k]! += v }
        else if let t = toolbar[k] { toolbar[k] = (t.any + v.map { $0.lowercased() }, t.not) }
    }
}
loadLabelOverrides()

func out(_ msg: String, _ code: Int32 = 0) -> Never {
    print(msg)
    exit(code)
}

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

func label(_ e: AXUIElement) -> String {
    (attr(e, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        ?? (attr(e, kAXDescriptionAttribute) as? String) ?? ""
}

/// Breadth-first search for a button whose label equals (or, for names, starts with) one of `names`.
func findToolbarButton(in root: AXUIElement, any: [String], not: [String]) -> AXUIElement? {
    var queue = [root]
    var i = 0
    while i < queue.count && i < 4000 {
        let e = queue[i]; i += 1
        if attr(e, kAXRoleAttribute) as? String == kAXButtonRole as String {
            let l = label(e).lowercased()
            if !l.isEmpty, l.count < 40, any.contains(where: { l.contains($0) }), !not.contains(where: { l.contains($0) }) {
                return e
            }
        }
        if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { queue += kids }
    }
    return nil
}

func findButton(in root: AXUIElement, names: [String]) -> AXUIElement? {
    var queue = [root]
    var i = 0
    while i < queue.count && i < 4000 {
        let e = queue[i]; i += 1
        if attr(e, kAXRoleAttribute) as? String == kAXButtonRole as String, names.contains(label(e)) {
            return e
        }
        if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { queue += kids }
    }
    return nil
}

func press(_ e: AXUIElement) {
    if AXUIElementPerformAction(e, kAXPressAction as CFString) == .success { return }
    // Fallback: real click at the element's centre.
    var pos = CGPoint.zero, size = CGSize.zero
    if let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) {
        AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
    }
    let c = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    let saved = CGEvent(source: nil)?.location ?? c
    for t in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
    CGWarpMouseCursorPosition(saved)
}

let action = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let bundleIds = ["com.microsoft.teams2", "com.microsoft.teams"]   // new Teams, classic Teams
guard action == "dump" || toolbar[action] != nil || reactions[action] != nil else { out("Unknown action: \(action)", 2) }
guard AXIsProcessTrusted() else { out("Grant Accessibility to the app running this script (Raycast or Vorssaint)", 1) }
guard let teams = bundleIds.compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }).first else {
    out("Teams not running", 1)
}
let app = AXUIElementCreateApplication(teams.processIdentifier)
// Teams' own meeting shortcuts (Cmd+Shift+key) are sent straight to the Teams process: no tree walk, no focus change.
// Set TEAMS_UI_MODE=ax to press the toolbar buttons instead.
let shortcuts: [String: CGKeyCode] = ["mute": 46, "camera": 31, "hand": 40, "share": 14]   // M, O, K, E
if let key = shortcuts[action], ProcessInfo.processInfo.environment["TEAMS_UI_MODE"] != "ax" {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
        e?.flags = [.maskCommand, .maskShift]
        e?.postToPid(teams.processIdentifier)
        usleep(10_000)
    }
    out("Sent shortcut for \(action)")
}

// Teams exposes its web content to accessibility only when asked.
AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
if action == "dump" {
    for w in windows {
        print("== \(label(w).isEmpty ? (attr(w, kAXTitleAttribute) as? String ?? "?") : label(w))")
        var queue = [w], i = 0
        while i < queue.count && i < 4000 {
            let e = queue[i]; i += 1
            if attr(e, kAXRoleAttribute) as? String == kAXButtonRole as String { print("  button: \(label(e))") }
            if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { queue += kids }
        }
    }
    exit(0)
}

// While the reaction menu is open the toolbar leaves the tree, so also accept a window showing the emoji.
let markers = reactButton + (reactions[action] ?? [])
let meetingWindow = windows.first { findButton(in: $0, names: markers) != nil }
guard let win = meetingWindow else { out("No meeting window", 1) }

if let t = toolbar[action] {
    guard let b = findToolbarButton(in: win, any: t.any, not: t.not) else { out("\(action) button not found", 1) }
    if ProcessInfo.processInfo.environment["TEAMS_UI_DRY"] != nil { out("would press: \(label(b))") }
    press(b)
    out("Pressed \(action)")
}

let names = reactions[action]!
// Menu may already be open (it stays open until a pick), so look for the emoji first.
var emoji = findButton(in: win, names: names)
if emoji == nil {
    guard let react = findButton(in: win, names: reactButton) else { out("React button not found", 1) }
    press(react)
    for _ in 0..<20 {
        usleep(75_000)
        emoji = findButton(in: win, names: names)
        if emoji != nil { break }
    }
}
guard let target = emoji else { out("Reaction menu did not open", 1) }
press(target)
out("Sent \(action)")
