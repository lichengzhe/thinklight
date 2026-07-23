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

// Continuity iPhones and third-party webcams stay untouched; they are someone
// else's camera, not a status light.
func statusCameras() -> [AVCaptureDevice] {
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

guard !statusCameras().isEmpty else {
    fputs("thinklight: no usable camera found\n", stderr)
    exit(1)
}

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

final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Discard every frame — the sessions only exist to power the LEDs
    }
}
let sink = FrameSink()
let sinkQueue = DispatchQueue(label: "thinklight.sink")

// A session with no output never actually starts capturing, so the LED stays dark
func makeSession(for device: AVCaptureDevice) -> AVCaptureSession? {
    let session = AVCaptureSession()
    session.sessionPreset = .low
    guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
        fputs("thinklight: cannot open \(device.localizedName)\n", stderr)
        return nil
    }
    session.addInput(input)
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(sink, queue: sinkQueue)
    guard session.canAddOutput(output) else {
        fputs("thinklight: cannot add video output for \(device.localizedName)\n", stderr)
        return nil
    }
    session.addOutput(output)
    return session
}

signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }

func anySessionRunning() -> Bool {
    var anyRun = false
    let fm = FileManager.default
    for name in (try? fm.contentsOfDirectory(atPath: sessionsDir.path)) ?? [] {
        if name.hasPrefix(".") { continue }  // half-written temp files
        let file = sessionsDir.appendingPathComponent(name)
        let parts = ((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            .split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard let pid = Int32(parts.first ?? ""), kill(pid, 0) == 0 else {
            try? fm.removeItem(at: file)
            continue
        }
        // "idle" tokens from older versions meant "waiting on you" — no longer lit
        if parts.count > 1 && parts[1] == "idle" {
            try? fm.removeItem(at: file)
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

var sessions: [String: AVCaptureSession] = [:]  // keyed by camera uniqueID
var lit = false
while true {
    let shouldLight = anySessionRunning()
    if shouldLight != lit {
        if shouldLight {
            // Re-discover on every lighting so a Studio Display docked or
            // undocked since the last run joins or leaves the sync.
            let cameras = statusCameras()
            let ids = Set(cameras.map(\.uniqueID))
            sessions = sessions.filter { ids.contains($0.key) }
            for camera in cameras where sessions[camera.uniqueID] == nil {
                sessions[camera.uniqueID] = makeSession(for: camera)
            }
            for session in sessions.values { session.startRunning() }
        } else {
            for session in sessions.values { session.stopRunning() }
        }
        lit = shouldLight
    }
    Thread.sleep(forTimeInterval: 1)
}
