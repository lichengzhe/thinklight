import CoreMediaIO
import Foundation

// Hardware-level truth: enumerate CMIO devices and read
// kCMIODevicePropertyDeviceIsRunningSomewhere. If a camera reports RUNNING,
// its LED is physically lit — don't trust AVCaptureSession.isRunning or your eyes.
var propAddr = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
var dataSize: UInt32 = 0
CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &propAddr, 0, nil, &dataSize)
let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
var devices = [CMIOObjectID](repeating: 0, count: count)
var used: UInt32 = 0
CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &propAddr, 0, nil, dataSize, &used, &devices)

for dev in devices {
    var nameAddr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var name: CFString = "" as CFString
    let nameSize = UInt32(MemoryLayout<CFString>.size)
    var nameUsed: UInt32 = 0
    withUnsafeMutablePointer(to: &name) { ptr in
        _ = CMIOObjectGetPropertyData(dev, &nameAddr, 0, nil, nameSize, &nameUsed, ptr)
    }

    var runAddr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var isRunning: UInt32 = 0
    let runSize = UInt32(MemoryLayout<UInt32>.size)
    var runUsed: UInt32 = 0
    CMIOObjectGetPropertyData(dev, &runAddr, 0, nil, runSize, &runUsed, &isRunning)

    print("\(name as String): \(isRunning == 1 ? "RUNNING (LED on)" : "idle")")
}
