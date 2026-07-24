import AVFoundation
import Foundation

// ThinkLight daemon: hold the status cameras so their LEDs become status
// lights — the Mac's built-in camera, plus any Studio Display camera so every
// display shows its own 🟢. Once a second it reads the session tokens (each
// file starts with the owner pid): any live session running -> LEDs on; none
// -> LEDs off, then wait for the next session.
//
// Tokens whose recorded process has exited are deleted here, so a crashed
// session can never leave the LED stuck on.
//
// The CLI launches this through launchd, making the daemon its own TCC
// "responsible process": macOS pins the camera use on thinklight-daemon
// instead of drawing a green camera pill in the menu bar that blames the
// hosting terminal. (An earlier multi-light version was scrapped over that
// pill, misread as an external-camera artifact — it was attribution.)
let stateDir = ProcessInfo.processInfo.environment["THINKLIGHT_STATE_DIR"].map {
    URL(fileURLWithPath: $0, isDirectory: true)
} ?? FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/state/thinklight", isDirectory: true)
let sessionsDir = stateDir.appendingPathComponent("sessions", isDirectory: true)
// Integration tests exercise token cleanup without touching camera hardware.
let cameraFreeTestMode = ProcessInfo.processInfo.environment["THINKLIGHT_TEST_NO_CAMERA"] == "1"

// Continuity iPhones and third-party webcams stay untouched; they are someone
// else's camera, not a status light.
func statusCameras() -> [AVCaptureDevice] {
    if cameraFreeTestMode { return [] }
    let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external],
        mediaType: .video,
        position: .unspecified
    )
    return discovery.devices.filter { device in
        if device.isContinuityCamera { return false }
        if device.manufacturer == "Apple Inc." && device.localizedName.contains("Studio Display") {
            return true
        }
        return device.deviceType == .builtInWideAngleCamera
    }
}

guard cameraFreeTestMode || !statusCameras().isEmpty else {
    fputs("thinklight: no usable camera found\n", stderr)
    exit(1)
}

if !cameraFreeTestMode {
    let sema = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var granted = false
    AVCaptureDevice.requestAccess(for: .video) { ok in
        granted = ok
        sema.signal()
    }
    sema.wait()
    guard granted else {
        fputs("thinklight: camera permission denied (grant it in System Settings > Privacy & Security > Camera)\n", stderr)
        exit(2)
    }
}

final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Discard every frame — the sessions only exist to power the LEDs
    }
}
let sink = FrameSink()
let sinkQueue = DispatchQueue(label: "thinklight.sink")

var sessions: [String: AVCaptureSession] = [:]  // keyed by camera uniqueID
// A camera that refuses to open (still settling right after a display is
// plugged in, or held by something else) is retried a few ticks later instead
// of every second, and only complains the first time.
var openRetryTicks: [String: Int] = [:]
var reportedOpenFailures: Set<String> = []
let openRetryDelay = 5

// A session with no output never actually starts capturing, so the LED stays dark
func makeSession(for device: AVCaptureDevice) -> AVCaptureSession? {
    func report(_ message: String) {
        guard reportedOpenFailures.insert(device.uniqueID).inserted else { return }
        fputs(message, stderr)
    }
    let session = AVCaptureSession()
    session.sessionPreset = .low
    guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
        report("thinklight: cannot open \(device.localizedName)\n")
        return nil
    }
    session.addInput(input)
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(sink, queue: sinkQueue)
    guard session.canAddOutput(output) else {
        report("thinklight: cannot add video output for \(device.localizedName)\n")
        return nil
    }
    session.addOutput(output)
    return session
}

// Re-discover on every lit tick, not just on the dark -> lit edge: a Studio
// Display docked in the middle of a turn has to join the sync right away, and
// one undocked mid-turn must not leave a stale session behind.
func syncLitCameras() {
    let cameras = statusCameras()
    let ids = Set(cameras.map(\.uniqueID))
    for (id, session) in sessions where !ids.contains(id) {
        session.stopRunning()
        sessions.removeValue(forKey: id)
    }
    openRetryTicks = openRetryTicks.filter { ids.contains($0.key) }
    reportedOpenFailures.formIntersection(ids)
    for camera in cameras where sessions[camera.uniqueID] == nil {
        if let wait = openRetryTicks[camera.uniqueID], wait > 0 {
            openRetryTicks[camera.uniqueID] = wait - 1
            continue
        }
        guard let session = makeSession(for: camera) else {
            openRetryTicks[camera.uniqueID] = openRetryDelay
            continue
        }
        openRetryTicks.removeValue(forKey: camera.uniqueID)
        reportedOpenFailures.remove(camera.uniqueID)
        sessions[camera.uniqueID] = session
    }
    for session in sessions.values where !session.isRunning { session.startRunning() }
}

signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }

struct TranscriptCursor {
    var offset: UInt64
    var pending = Data()
    var discardingPartialLine: Bool
}

var transcriptCursors: [String: TranscriptCursor] = [:]
let transcriptLookbackBytes: UInt64 = 128 * 1024

func isTerminalEvent(_ line: Data, turnID: String) -> Bool {
    let mentionsTurn = line.range(of: Data(turnID.utf8)) != nil
    let mentionsTerminalEvent =
        line.range(of: Data("turn_aborted".utf8)) != nil
        || line.range(of: Data("task_complete".utf8)) != nil
    guard
        mentionsTurn,
        mentionsTerminalEvent,
        let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
        object["type"] as? String == "event_msg",
        let payload = object["payload"] as? [String: Any],
        payload["turn_id"] as? String == turnID,
        let event = payload["type"] as? String
    else {
        return false
    }
    return event == "turn_aborted" || event == "task_complete"
}

// Codex does not run Stop when Ctrl+C interrupts a turn. Its hook payload does
// provide transcript_path and turn_id, so watch only the newly appended JSONL
// for that turn's terminal event. This is best-effort because Codex documents
// the transcript format as unstable; the normal Stop/SessionEnd hooks and
// owner-pid cleanup remain the primary paths.
func codexTurnEnded(tokenName: String, transcriptPath: String, turnID: String) -> Bool {
    guard !transcriptPath.isEmpty, !turnID.isEmpty else { return false }
    let url = URL(fileURLWithPath: transcriptPath)
    guard
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        let fileSize = attributes[.size] as? NSNumber
    else {
        return false
    }

    let size = fileSize.uint64Value
    var cursor: TranscriptCursor
    if let existing = transcriptCursors[tokenName], size >= existing.offset {
        cursor = existing
    } else {
        let start = size > transcriptLookbackBytes ? size - transcriptLookbackBytes : 0
        cursor = TranscriptCursor(offset: start, discardingPartialLine: start > 0)
    }
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    do {
        try handle.seek(toOffset: cursor.offset)
    } catch {
        return false
    }
    guard let fresh = try? handle.readToEnd(), !fresh.isEmpty else {
        transcriptCursors[tokenName] = cursor
        return false
    }
    cursor.offset += UInt64(fresh.count)

    var bytes = cursor.pending
    bytes.append(fresh)
    cursor.pending.removeAll(keepingCapacity: true)

    var start = bytes.startIndex
    var ended = false
    for newline in bytes.indices where bytes[newline] == 0x0a {
        if cursor.discardingPartialLine {
            cursor.discardingPartialLine = false
        } else if isTerminalEvent(bytes.subdata(in: start..<newline), turnID: turnID) {
            ended = true
        }
        start = bytes.index(after: newline)
    }
    if start < bytes.endIndex && !cursor.discardingPartialLine {
        let tail = bytes.subdata(in: start..<bytes.endIndex)
        if isTerminalEvent(tail, turnID: turnID) {
            ended = true
        } else {
            cursor.pending = tail
        }
    }
    transcriptCursors[tokenName] = cursor
    return ended
}

func anySessionRunning() -> Bool {
    var anyRun = false
    let fm = FileManager.default
    let names = (try? fm.contentsOfDirectory(atPath: sessionsDir.path)) ?? []
    let visibleNames = Set(names.filter { !$0.hasPrefix(".") })
    transcriptCursors = transcriptCursors.filter { visibleNames.contains($0.key) }
    for name in visibleNames {
        let file = sessionsDir.appendingPathComponent(name)
        let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let lines = contents.components(separatedBy: .newlines)
        let pidText = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let pid = Int32(pidText), kill(pid, 0) == 0 else {
            try? fm.removeItem(at: file)
            transcriptCursors.removeValue(forKey: name)
            continue
        }
        // "idle" tokens from older versions meant "waiting on you" — no longer lit
        if lines.count > 1 && lines[1] == "idle" {
            try? fm.removeItem(at: file)
            transcriptCursors.removeValue(forKey: name)
            continue
        }
        let transcriptPath = lines.count > 1 ? lines[1] : ""
        let turnID = lines.count > 2
            ? lines[2].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        if codexTurnEnded(tokenName: name, transcriptPath: transcriptPath, turnID: turnID) {
            try? fm.removeItem(at: file)
            transcriptCursors.removeValue(forKey: name)
            continue
        }
        anyRun = true
    }
    return anyRun
}

FileHandle.standardOutput.write(
    "thinklight: watching sessions, LEDs via \(statusCameras().map(\.localizedName).joined(separator: " + ")), pid \(ProcessInfo.processInfo.processIdentifier)\n"
        .data(using: .utf8)!
)

var lit = false
func tick() {
    let shouldLight = anySessionRunning()
    if shouldLight {
        syncLitCameras()
    } else if lit {
        for session in sessions.values { session.stopRunning() }
    }
    lit = shouldLight
}

// The once-a-second tick runs on the main run loop rather than a sleep loop.
// AVFoundation refreshes its cached device list from run-loop notifications, so
// a daemon that never runs one keeps listing a Studio Display long after its
// cable is pulled — and keeps a session that looks alive but captures nothing,
// leaving that display dark for the rest of the daemon's life.
final class Ticker: NSObject {
    @objc func onTimer() { tick() }
}
let ticker = Ticker()
let timer = Timer(
    timeInterval: 1, target: ticker, selector: #selector(Ticker.onTimer),
    userInfo: nil, repeats: true
)
RunLoop.main.add(timer, forMode: .common)
timer.fire()
RunLoop.main.run()
