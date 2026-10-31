#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

// The deprecated public Carbon Alias Manager is isolated in C because modern
// Swift does not import its FSRef/Handle types. Creates memory data only.
CFDataRef _Nullable FolderTermCreateLegacyAliasData(CFURLRef _Nonnull url,
                                                   int32_t * _Nonnull status) CF_RETURNS_RETAINED;
