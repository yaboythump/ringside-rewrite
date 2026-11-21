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

/* melonDS ships the same blip_buf library; give mGBA's copy its own symbol names. */
#define blip_add_delta mgba_blip_add_delta
#define blip_add_delta_fast mgba_blip_add_delta_fast
#define blip_clear mgba_blip_clear
#define blip_clocks_needed mgba_blip_clocks_needed
#define blip_delete mgba_blip_delete
#define blip_end_frame mgba_blip_end_frame
#define blip_new mgba_blip_new
#define blip_read_samples mgba_blip_read_samples
#define blip_samples_avail mgba_blip_samples_avail
#define blip_set_rates mgba_blip_set_rates
#ifdef __APPLE__
#include <xlocale.h>
#endif
#endif
