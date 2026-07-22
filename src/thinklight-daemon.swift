import AVFoundation
import Foundation

// Hold both the Mac's built-in camera and an attached Studio Display camera.
// Other external cameras and Continuity Camera iPhones are deliberately skipped.
let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .external],
    mediaType: .video,
    position: .unspecified
)
let discoveredDevices = discovery.devices.filter { !$0.isContinuityCamera }
func isStudioDisplayCamera(_ device: AVCaptureDevice) -> Bool {
    device.manufacturer == "Apple Inc." && device.localizedName.contains("Studio Display")
}
let builtInDevices = discoveredDevices.filter {
    $0.deviceType == .builtInWideAngleCamera && !isStudioDisplayCamera($0)
}
let studioDisplayDevices = discoveredDevices.filter(isStudioDisplayCamera)

let target = CommandLine.arguments.dropFirst().first ?? "built-in"
if target == "has-studio" {
    exit(studioDisplayDevices.isEmpty ? 1 : 0)
}

let devices: [AVCaptureDevice]
switch target {
case "built-in":
    devices = builtInDevices
case "studio":
    devices = studioDisplayDevices
default:
    fputs("usage: thinklight-daemon [built-in|studio|has-studio]\n", stderr)
    exit(64)
}

guard !devices.isEmpty else {
    fputs("thinklight: no camera found for target '\(target)'\n", stderr)
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

final class CameraHold {
    let device: AVCaptureDevice
    let session: AVCaptureSession
    let sink: FrameSink

    init?(device: AVCaptureDevice) {
        let session = AVCaptureSession()
        session.sessionPreset = .low
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            fputs("thinklight: cannot open \(device.localizedName)\n", stderr)
            return nil
        }
        session.addInput(input)

        // A session with no output never captures, so its LED stays dark.
        let sink = FrameSink()
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(
            sink,
            queue: DispatchQueue(label: "thinklight.sink.\(device.uniqueID)")
        )
        guard session.canAddOutput(output) else {
            fputs("thinklight: cannot add video output for \(device.localizedName)\n", stderr)
            return nil
        }
        session.addOutput(output)
        session.startRunning()
        guard session.isRunning else {
            fputs("thinklight: failed to start \(device.localizedName)\n", stderr)
            return nil
        }

        self.device = device
        self.session = session
        self.sink = sink
    }
}

let holds = devices.compactMap { CameraHold(device: $0) }
guard !holds.isEmpty else { exit(3) }

let names = holds.map { $0.device.localizedName }.joined(separator: " + ")
FileHandle.standardOutput.write(
    "thinklight: LEDs on via \(names), pid \(ProcessInfo.processInfo.processIdentifier)\n"
        .data(using: .utf8)!
)

signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }
RunLoop.main.run()
