// Build options for the vendored rcheevos (RetroAchievements) library, included before each
// of its sources by the generated units and by RDAchievements.c.
#ifndef RETRO_DUO_ACHIEVEMENTS_CONFIG_H
#define RETRO_DUO_ACHIEVEMENTS_CONFIG_H
#define RC_CLIENT_SUPPORTS_HASH 1

// rcheevos' few globals without an rc_ prefix, renamed so they can't clash with other libraries
// in the app (melonDS ships the same tiny-AES-c). Regenerate after updating rcheevos:
//   nm -g --defined-only on its objects, every name not starting with rc_.
#define AES_CBC_decrypt_buffer rc_AES_CBC_decrypt_buffer
#define AES_CTR_xcrypt_buffer rc_AES_CTR_xcrypt_buffer
#define AES_ctx_set_iv rc_AES_ctx_set_iv
#define AES_init_ctx rc_AES_init_ctx
#define AES_init_ctx_iv rc_AES_init_ctx_iv
#define _rc_hash_jaguar_cd_homebrew_hash rc_hash_jaguar_cd_homebrew_hash_
#define g_host rc_g_host
#define md5_append rc_md5_append
#define md5_finish rc_md5_finish
#define md5_init rc_md5_init
#endif
