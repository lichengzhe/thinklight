import AVFoundation
import Foundation

// ThinkLight daemon: hold the Mac's built-in camera so its LED becomes a
// status light. Twice a second it reads the session tokens (each file is
// "<pid> <run|idle>") and drives one of three states:
//
//   any live session idle (waiting on you)  -> blink, 1.5s lit / 1.5s dark
//   any live session running                -> steady on
//   no live sessions                        -> light off, exit
//
// Tokens whose recorded process has exited are deleted here, so a crashed
// session can never leave the LED stuck on.
let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/state/thinklight/sessions")

let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera],
    mediaType: .video,
    position: .unspecified
)
// A Studio Display's camera also reports .builtInWideAngleCamera and can
// enumerate ahead of the Mac's own; only the true built-in LED is wanted
// (external cameras make macOS draw a green camera icon in the menu bar).
guard let device = discovery.devices.first(where: {
    !$0.isContinuityCamera
        && !($0.manufacturer == "Apple Inc." && $0.localizedName.contains("Studio Display"))
}) else {
    fputs("thinklight: no built-in camera found\n", stderr)
    exit(1)
}

let sema = DispatchSemaphore(value: 0)
var granted = false
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
        // Discard every frame — the session only exists to power the LED
    }
}

let session = AVCaptureSession()
session.sessionPreset = .low
guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
    fputs("thinklight: cannot open \(device.localizedName)\n", stderr)
    exit(3)
}
session.addInput(input)

// A session with no output never actually starts capturing, so the LED stays dark
let sink = FrameSink()
let output = AVCaptureVideoDataOutput()
output.alwaysDiscardsLateVideoFrames = true
output.setSampleBufferDelegate(sink, queue: DispatchQueue(label: "thinklight.sink"))
guard session.canAddOutput(output) else {
    fputs("thinklight: cannot add video output\n", stderr)
    exit(4)
}
session.addOutput(output)

signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }

enum Want { case steady, blink, quit }

func poll() -> Want {
    var anyRun = false, anyIdle = false
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
        // Tokens from older versions carry a backend name here; count them as running
        if parts.count > 1 && parts[1] == "idle" { anyIdle = true } else { anyRun = true }
    }
    if anyIdle { return .blink }
    if anyRun { return .steady }
    return .quit
}

var lit = false
func setLit(_ on: Bool) {
    guard on != lit else { return }
    if on { session.startRunning() } else { session.stopRunning() }
    lit = on
}

FileHandle.standardOutput.write(
    "thinklight: watching sessions, LED via \(device.localizedName), pid \(ProcessInfo.processInfo.processIdentifier)\n"
        .data(using: .utf8)!
)

var tick = 0
while true {
    switch poll() {
    case .quit:
        setLit(false)
        exit(0)
    case .steady:
        setLit(true)
        tick = 0
    case .blink:
        setLit(tick % 6 < 3)
        tick += 1
    }
    Thread.sleep(forTimeInterval: 0.5)
}
