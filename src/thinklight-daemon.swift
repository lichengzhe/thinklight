import AVFoundation
import Foundation

// Select the built-in camera only, skipping Studio Display / Continuity cameras
let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera],
    mediaType: .video,
    position: .unspecified
)
guard let device = discovery.devices.first else {
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

session.startRunning()
FileHandle.standardOutput.write("thinklight: LED on via \(device.localizedName), pid \(ProcessInfo.processInfo.processIdentifier)\n".data(using: .utf8)!)

signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }
RunLoop.main.run()
