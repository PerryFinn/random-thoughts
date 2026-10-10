import CoreServices
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct AppLaunchTests {
    @Test func recognizesLoginLaunchOnlyFromTheOpenApplicationEvent() {
        #expect(AppLaunchReasonDetector.reason(for: nil) == .user)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        #expect(AppLaunchReasonDetector.reason(for: event) == .user)
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        #expect(AppLaunchReasonDetector.reason(for: event) == .login)

        let reopen = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        reopen.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        #expect(AppLaunchReasonDetector.reason(for: reopen) == .user)
    }
}
