#ifndef RandomThoughtsSystemBridge_h
#define RandomThoughtsSystemBridge_h

#include <stdbool.h>
#include <dispatch/dispatch.h>

typedef enum {
    RTMediaCommandPlay = 0,
    RTMediaCommandPause = 1,
} RTMediaCommand;

typedef void (^RTNowPlayingStateHandler)(bool isPlaying);

void RTWakeDisplay(void);
void RTSleepDisplay(void);
int RTLockScreenImmediate(void);
void RTGetNowPlayingApplicationIsPlaying(
    dispatch_queue_t queue,
    RTNowPlayingStateHandler handler
);
bool RTSendMediaCommand(RTMediaCommand command);

#endif
