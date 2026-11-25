// Build settings for the vendored SameBoy core. Xcode injects this file into
// every C file in the target (GCC_PREFIX_HEADER), and the Linux core test uses
// it the same way with `-include`, so both builds compile identical code.
#ifndef RETRO_DUO_SAMEBOY_CONFIG_H
#define RETRO_DUO_SAMEBOY_CONFIG_H

#ifndef __OBJC__
#define GB_INTERNAL 1
#define GB_DISABLE_DEBUGGER 1
#define GB_DISABLE_CHEAT_SEARCH 1
#define GB_DISABLE_REWIND 1
#define GB_VERSION "1.0.5"
#define GB_COPYRIGHT_YEAR "2026"
#endif

#endif
