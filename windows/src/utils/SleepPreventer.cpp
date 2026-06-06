#include "SleepPreventer.h"
#include <windows.h>

void SleepPreventer::preventSleep() {
    SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
}

void SleepPreventer::allowSleep() {
    SetThreadExecutionState(ES_CONTINUOUS);
}
