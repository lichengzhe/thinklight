import CoreMediaIO
import Foundation

func requireSuccess(_ status: OSStatus, _ operation: String) {
    guard status == noErr else {
        fputs("thinklight-check: \(operation) failed (OSStatus \(status))\n", stderr)
        exit(1)
    }
}

// Hardware-level truth: enumerate CMIO devices and read
// kCMIODevicePropertyDeviceIsRunningSomewhere. If a camera reports RUNNING,
// its LED is physically lit — don't trust AVCaptureSession.isRunning or your eyes.
var propAddr = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
var dataSize: UInt32 = 0
requireSuccess(
    CMIOObjectGetPropertyDataSize(
        CMIOObjectID(kCMIOObjectSystemObject), &propAddr, 0, nil, &dataSize
    ),
    "enumerating camera devices"
)
let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
guard count > 0 else {
    fputs("thinklight-check: no camera devices found\n", stderr)
    exit(1)
}

var devices = [CMIOObjectID](repeating: 0, count: count)
var used: UInt32 = 0
requireSuccess(
    CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject), &propAddr, 0, nil, dataSize, &used, &devices
    ),
    "reading camera devices"
)

for dev in devices {
    var nameAddr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var name: CFString = "" as CFString
    let nameSize = UInt32(MemoryLayout<CFString>.size)
    var nameUsed: UInt32 = 0
    let nameStatus = withUnsafeMutablePointer(to: &name) { ptr in
        CMIOObjectGetPropertyData(dev, &nameAddr, 0, nil, nameSize, &nameUsed, ptr)
    }
    requireSuccess(nameStatus, "reading camera \(dev) name")

    var runAddr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var isRunning: UInt32 = 0
    let runSize = UInt32(MemoryLayout<UInt32>.size)
    var runUsed: UInt32 = 0
    requireSuccess(
        CMIOObjectGetPropertyData(
            dev, &runAddr, 0, nil, runSize, &runUsed, &isRunning
        ),
        "reading \(name as String) state"
    )

    print("\(name as String): \(isRunning == 1 ? "RUNNING (LED on)" : "idle")")
}
