#include "ToolbarAliasBridge.h"
#include <CoreServices/CoreServices.h>

CFDataRef FolderTermCreateLegacyAliasData(CFURLRef url, int32_t *status) {
    FSRef reference;
    if (!CFURLGetFSRef(url, &reference)) {
        *status = fnfErr;
        return NULL;
    }
    AliasHandle alias = NULL;
    *status = FSNewAliasMinimal(&reference, &alias);
    if (*status != noErr || alias == NULL) return NULL;
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)*alias, GetAliasSize(alias));
    DisposeHandle((Handle)alias);
    if (data == NULL) *status = memFullErr;
    return data;
}
