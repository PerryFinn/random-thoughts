import CoreServices
import Foundation

enum AppLaunchReasonDetector {
    static func reason(for event: NSAppleEventDescriptor?) -> AppLaunchReason {
        guard event?.eventID == AEEventID(kAEOpenApplication),
              event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem) else {
            return .user
        }
        return .login
    }
}
