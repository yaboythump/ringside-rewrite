// Build options for the vendored mGBA core, matching mGBA's own CMake configuration
// for a GBA-only static library without zip, png, sqlite or scripting.
#ifndef RETRO_DUO_GBA_CONFIG_H
#define RETRO_DUO_GBA_CONFIG_H
#define BUILD_STATIC 1
#define M_CORE_GBA 1
#define USE_PTHREADS 1
#define HAVE_LOCALE 1
#define HAVE_NEWLOCALE 1
#define HAVE_FREELOCALE 1
#define HAVE_USELOCALE 1
#define HAVE_SETLOCALE 1
#define HAVE_LOCALTIME_R 1
#define HAVE_STRDUP 1
#define HAVE_STRNDUP 1
#define HAVE_STRLCPY 1
#define HAVE_VASPRINTF 1
#define HAVE_FUTIMENS 1
#define HAVE_FUTIMES 1
#define HAVE_PTHREAD_CREATE 1
#define HAVE_PTHREAD_SETNAME_NP 1
#ifdef __APPLE__
#include <xlocale.h>
#endif
#endif
