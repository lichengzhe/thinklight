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
// What a token from another machine writes where a local one writes its pid.
let remoteMarker = "remote"
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
        // A session on another machine has no pid worth asking about here — the
        // number would name some unrelated local process. Its liveness is the
        // socket connection that registered it, and this file exists only for
        // as long as that connection does (see the remote sessions section).
        if pidText == remoteMarker {
            anyRun = true
            continue
        }
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

// The LED only reports where you can see it; the soundtrack reports anywhere in
// the room. Tracks live next to the install rather than inside the binary, so
// swapping one is a file copy instead of a rebuild.
let soundDir = ProcessInfo.processInfo.environment["THINKLIGHT_SHARE_DIR"].map {
    URL(fileURLWithPath: $0, isDirectory: true)
} ?? FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/share/thinklight", isDirectory: true)
let soundFlag = soundDir.appendingPathComponent("sound-on")

// Matched by stem rather than by a fixed name, so any format macOS can decode
// works: loop.mp3 plays as readily as loop.flac.
func trackURL(stem: String) -> URL? {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: soundDir.path)
    else { return nil }
    guard let name = names.filter({ ($0 as NSString).deletingPathExtension == stem })
        .sorted().first
    else { return nil }
    return soundDir.appendingPathComponent(name)
}

// A missing track is not worth refusing to run over — the light still works
// without the sound.
func loadTrack(_ stem: String, loops: Int) -> AVAudioPlayer? {
    guard let url = trackURL(stem: stem),
        let player = try? AVAudioPlayer(contentsOf: url)
    else {
        fputs("thinklight: no \(stem) track in \(soundDir.path); that cue stays silent\n", stderr)
        return nil
    }
    player.numberOfLoops = loops
    player.prepareToPlay()
    return player
}

var runningTrack: AVAudioPlayer?
var doneTrack: AVAudioPlayer?
var soundOn = false

// Sound is opt-in, and the flag is re-read every tick so `thinklight unmute`
// lands inside the turn that ran it instead of waiting for a restart. Players
// are built on that switch rather than on the light's own transition: decoding
// at a turn boundary would push the cue past the moment it exists to mark,
// while flipping the switch is a deliberate act with no deadline. Muted, the
// daemon touches no audio API at all.
func syncSound() {
    let wanted = FileManager.default.fileExists(atPath: soundFlag.path)
    if wanted == soundOn { return }
    if wanted {
        runningTrack = loadTrack("loop", loops: -1)
        doneTrack = loadTrack("done", loops: 0)
        // Unmuting while the agent is already working belongs on the loop now,
        // not at the next turn — otherwise the command looks like it did nothing.
        if lit { runningTrack?.play() }
    } else {
        runningTrack?.stop()
        doneTrack?.stop()
        runningTrack = nil
        doneTrack = nil
    }
    soundOn = wanted
}

// MARK: - Sessions on other machines
//
// The light is a Mac camera LED, but the agent often runs somewhere else: an ssh
// session on a build box, or another Mac nobody is looking at. That agent cannot
// write into this state directory, so it speaks over a Unix socket instead —
// `thinklight tunnel setup` hands the socket to ssh as a RemoteForward, and the
// hook on the far side finds the forwarded port open and sends its on/off back
// down the connection you were already using.
//
// An `on` connection is then held open for the length of the turn, and the token
// it registers lives exactly as long as it does. That is the entire liveness
// story, and it is the reason a remote token records no pid: a pid from another
// machine names some unrelated local process here, while a dropped ssh, a killed
// agent, or a closed laptop lid tears the connection down by itself. `off`
// arrives on a second connection and closes the held one, which is also how the
// far side learns the turn it was holding is over.
let remoteSocketPath = stateDir.appendingPathComponent("ipc.sock").path
let remoteProtocol = "thinklight1"
// Remote tokens are named "@host.key". The CLI only ever names a token from
// [A-Za-z0-9._-], so the prefix is one character no local session can produce.
let remoteTokenPrefix = "@"
let remoteLinkLimit = 128

final class RemoteLink {
    let fd: Int32
    var source: DispatchSourceRead?
    var pending = Data()
    var tokens: Set<String> = []
    init(fd: Int32) { self.fd = fd }
}

var remoteLinks: [Int32: RemoteLink] = [:]
var remoteListenerSource: DispatchSourceRead?
var remoteTokenSerial = 0

// Every field a remote sends ends up in a filename, so it is held to the same
// shape the CLI requires of a session id before either is joined to a path.
func isSafeRemoteName(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 128, !value.hasPrefix("."), !value.contains("..")
    else { return false }
    return value.allSatisfy { character in
        character.isASCII
            && (character.isLetter || character.isNumber
                || character == "." || character == "_" || character == "-")
    }
}

func remoteTokenNames() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir.path)) ?? []
    return names.filter { $0.hasPrefix(remoteTokenPrefix) }
}

func recordedSessionKey(_ name: String) -> String {
    let contents =
        (try? String(contentsOf: sessionsDir.appendingPathComponent(name), encoding: .utf8)) ?? ""
    let lines = contents.components(separatedBy: .newlines)
    return lines.count > 3 ? lines[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""
}

// The same four lines and the same write-then-rename the CLI uses, so nothing
// reading this directory has to know which kind of token it is holding. The
// transcript and turn lines stay empty: they exist for Codex's interrupted-turn
// detection, which reads a local transcript the far side does not have.
func writeRemoteToken(name: String, sessionKey: String) -> Bool {
    let fm = FileManager.default
    try? fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    remoteTokenSerial += 1
    let temp = sessionsDir.appendingPathComponent(".tok.remote.\(getpid()).\(remoteTokenSerial)")
    let body = "\(remoteMarker)\n\n\n\(sessionKey)\n"
    guard (try? body.write(to: temp, atomically: false, encoding: .utf8)) != nil else { return false }
    guard rename(temp.path, sessionsDir.appendingPathComponent(name).path) == 0 else {
        try? fm.removeItem(at: temp)
        return false
    }
    return true
}

func closeRemoteLink(_ link: RemoteLink) {
    guard remoteLinks.removeValue(forKey: link.fd) != nil else { return }
    link.source?.cancel()
    link.source = nil
    for name in link.tokens {
        try? FileManager.default.removeItem(at: sessionsDir.appendingPathComponent(name))
    }
    link.tokens.removeAll()
}

// Closing the connection that registered the token is not cleanup, it is the
// message: the far side is blocked reading it, and the close is what tells it
// the turn is over.
func dropRemoteToken(_ name: String) {
    try? FileManager.default.removeItem(at: sessionsDir.appendingPathComponent(name))
    for link in Array(remoteLinks.values) where link.tokens.contains(name) {
        closeRemoteLink(link)
    }
}

func handleRemoteLine(_ raw: String, on link: RemoteLink) {
    let fields = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
    guard fields.count == 5, fields[0] == remoteProtocol else {
        closeRemoteLink(link)
        return
    }
    let (verb, host, key, sessionKey) = (fields[1], fields[2], fields[3], fields[4])
    guard isSafeRemoteName(host), isSafeRemoteName(key), isSafeRemoteName(sessionKey) else {
        closeRemoteLink(link)
        return
    }
    let stem = remoteTokenPrefix + host + "."

    switch verb {
    case "clear":
        // `thinklight off --force` on the far side. That means "light off, now",
        // so everything that machine registered goes with it.
        for name in remoteTokenNames() where name.hasPrefix(stem) { dropRemoteToken(name) }
        closeRemoteLink(link)
    case "on":
        guard link.tokens.isEmpty, writeRemoteToken(name: stem + key, sessionKey: sessionKey) else {
            closeRemoteLink(link)
            return
        }
        link.tokens.insert(stem + key)
    case "off":
        var doomed: Set<String> = [stem + key]
        if key != sessionKey {
            // A turn-scoped token is the one that matters, but a CLI from before
            // turn ids — or an upgrade mid-turn — can have left a per-session one.
            doomed.insert(stem + sessionKey)
        } else {
            // No turn id means a session ending, and its turn-scoped tokens end
            // with it. A session id may itself contain dots, so the prefix alone
            // could match a different session; the recorded key disambiguates.
            for candidate in remoteTokenNames()
            where candidate.hasPrefix(stem + sessionKey + ".")
                && recordedSessionKey(candidate) == sessionKey {
                doomed.insert(candidate)
            }
        }
        for name in doomed { dropRemoteToken(name) }
        // `off` is one-shot: it holds nothing, so there is nothing to wait for.
        closeRemoteLink(link)
    default:
        closeRemoteLink(link)
        return
    }
    // Rather than up to a second later. A turn boundary is exactly the moment
    // this light exists to mark, and the far side already paid a round trip.
    tick()
}

func remoteReadable(_ link: RemoteLink) {
    var buffer = [UInt8](repeating: 0, count: 1024)
    let count = read(link.fd, &buffer, buffer.count)
    if count < 0 {
        if errno == EAGAIN || errno == EINTR { return }
        closeRemoteLink(link)
        return
    }
    // End of file: the far side is gone, and so is whatever it was holding.
    if count == 0 {
        closeRemoteLink(link)
        return
    }
    link.pending.append(contentsOf: buffer[0..<count])
    // Nothing that speaks this protocol sends a line anywhere near this long.
    if link.pending.count > 4096 {
        closeRemoteLink(link)
        return
    }
    while let newline = link.pending.firstIndex(of: 0x0a) {
        let line = link.pending.subdata(in: link.pending.startIndex..<newline)
        link.pending.removeSubrange(link.pending.startIndex...newline)
        handleRemoteLine(String(decoding: line, as: UTF8.self), on: link)
        // The line may have closed this link; its buffer is gone with it.
        if remoteLinks[link.fd] == nil { return }
    }
}

func acceptRemoteLinks(_ listener: Int32) {
    while true {
        let fd = accept(listener, nil, nil)
        guard fd >= 0 else { return }
        guard remoteLinks.count < remoteLinkLimit else {
            close(fd)
            continue
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        // The far side connected to a port number, which could belong to
        // anything. Saying what this is before it sends a session is what lets
        // it tell a forwarded ThinkLight socket from some unrelated local service.
        let greeting = remoteProtocol + "\n"
        _ = greeting.withCString { write(fd, $0, strlen($0)) }
        let link = RemoteLink(fd: fd)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { remoteReadable(link) }
        source.setCancelHandler { close(fd) }
        link.source = source
        remoteLinks[fd] = link
        source.resume()
    }
}

// Tokens left by a daemon that is gone. Their connections died with it, so
// nothing is holding them up any more.
func purgeRemoteTokens() {
    for name in remoteTokenNames() {
        try? FileManager.default.removeItem(at: sessionsDir.appendingPathComponent(name))
    }
}

// `thinklight off --force` empties the state directory behind the daemon's back.
// A holder whose token went with it is holding nothing, and the far side is
// still blocked on this connection waiting to hear so.
func pruneRemoteLinks() {
    let fm = FileManager.default
    for link in Array(remoteLinks.values) where !link.tokens.isEmpty {
        let orphaned = link.tokens.contains {
            !fm.fileExists(atPath: sessionsDir.appendingPathComponent($0).path)
        }
        if orphaned { closeRemoteLink(link) }
    }
    // And the mirror image: a remote token nothing is holding up. Only this
    // daemon writes these, and it deletes them with their connection, so one
    // surviving on its own means something else put it there. Left alone it
    // would light the LED for the rest of the daemon's life, since the whole
    // point of a remote token is that there is no pid here to ask about it.
    let held = Set(remoteLinks.values.flatMap { $0.tokens })
    for name in remoteTokenNames() where !held.contains(name) {
        try? fm.removeItem(at: sessionsDir.appendingPathComponent(name))
    }
}

func startRemoteListener() {
    // sun_path is 104 bytes on Darwin, which a home directory is in no danger of
    // exhausting; a test running out of a deep temporary directory could.
    guard remoteSocketPath.utf8.count < 104 else {
        fputs("thinklight: state path too long for a socket, remote sessions are off\n", stderr)
        return
    }
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    // Only one daemon runs at a time, so any socket file here is from one that
    // has exited and nothing is listening on it.
    unlink(remoteSocketPath)

    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listener >= 0 else {
        fputs("thinklight: cannot create the remote session socket\n", stderr)
        return
    }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    withUnsafeMutablePointer(to: &address.sun_path) { field in
        field.withMemoryRebound(to: CChar.self, capacity: capacity) { path in
            _ = strlcpy(path, remoteSocketPath, capacity)
        }
    }
    // Bound under a tightened umask rather than chmod'ed afterwards: between the
    // two there would be a moment when the socket was open to the whole machine.
    let previousMask = umask(0o177)
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    umask(previousMask)
    guard bound == 0, listen(listener, 16) == 0 else {
        fputs("thinklight: cannot listen for remote sessions on \(remoteSocketPath)\n", stderr)
        close(listener)
        unlink(remoteSocketPath)
        return
    }
    _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL, 0) | O_NONBLOCK)
    let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
    source.setEventHandler { acceptRemoteLinks(listener) }
    source.setCancelHandler { close(listener) }
    remoteListenerSource = source
    source.resume()
}

func tick() {
    pruneRemoteLinks()
    syncSound()
    let shouldLight = anySessionRunning()
    if shouldLight {
        syncLitCameras()
        if !lit {
            // "You're up" goes stale the instant the next turn starts, so a new
            // turn cuts the chime off instead of letting the two tracks overlap.
            doneTrack?.stop()
            doneTrack?.currentTime = 0
            runningTrack?.currentTime = 0
            runningTrack?.play()
        }
    } else if lit {
        for session in sessions.values { session.stopRunning() }
        runningTrack?.stop()
        doneTrack?.currentTime = 0
        doneTrack?.play()
    }
    lit = shouldLight
}

// A far side that hangs up mid-write must cost one failed write, not the daemon.
signal(SIGPIPE, SIG_IGN)
purgeRemoteTokens()
atexit { unlink(remoteSocketPath) }
startRemoteListener()

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
