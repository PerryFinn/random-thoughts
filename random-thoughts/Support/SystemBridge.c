#include "SystemBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

extern int SACLockScreenImmediate(void);

typedef enum {
    MRCommandPlay = 0,
    MRCommandPause = 1,
} MRCommand;

typedef void (^MRNowPlayingStateHandler)(Boolean isPlaying);

extern void MRMediaRemoteGetNowPlayingApplicationIsPlaying(
    dispatch_queue_t queue,
    MRNowPlayingStateHandler handler
);
extern Boolean MRMediaRemoteSendCommand(MRCommand command, CFTypeRef userInfo);

void RTWakeDisplay(void)
{
    static IOPMAssertionID assertionID;
    IOPMAssertionDeclareUserActivity(
        CFSTR("随想蓝牙解锁"),
        kIOPMUserActiveLocal,
        &assertionID
    );
}

void RTSleepDisplay(void)
{
    io_registry_entry_t registryEntry = IORegistryEntryFromPath(
        kIOMainPortDefault,
        "IOService:/IOResources/IODisplayWrangler"
    );
    if (registryEntry) {
        IORegistryEntrySetCFProperty(
            registryEntry,
            CFSTR("IORequestIdle"),
            kCFBooleanTrue
        );
        IOObjectRelease(registryEntry);
    }
}

int RTLockScreenImmediate(void)
{
    return SACLockScreenImmediate();
}

void RTGetNowPlayingApplicationIsPlaying(
    dispatch_queue_t queue,
    RTNowPlayingStateHandler handler
)
{
    MRMediaRemoteGetNowPlayingApplicationIsPlaying(queue, ^(Boolean isPlaying) {
        handler(isPlaying);
    });
}

bool RTSendMediaCommand(RTMediaCommand command)
{
    return MRMediaRemoteSendCommand((MRCommand)command, NULL);
}
