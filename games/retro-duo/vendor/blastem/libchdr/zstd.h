#ifndef BLASTEM_ZSTD_STUB_H_
#define BLASTEM_ZSTD_STUB_H_

/*
 * libchdr can decompress five CHD codecs; four of them (zlib, lzma, huffman and
 * FLAC) are satisfied by what blastem already carries, and only zstd would pull
 * in a whole compression library of its own for the one codec chdman does not
 * use by default. This stands in for it: every stream fails to open, so a CHD
 * compressed with cdzs/zstd is reported as unreadable and every other CHD works.
 *
 * The point of doing it this way, rather than cutting the codec out of
 * libchdr_chd.c, is that the vendored libchdr sources stay byte for byte
 * identical to upstream and can be updated by copying over them. Dropping a
 * real zstd in its place is a matter of deleting these two files.
 */

#include <stddef.h>

typedef struct ZSTD_DStream_s ZSTD_DStream;

typedef struct {
	const void *src;
	size_t size;
	size_t pos;
} ZSTD_inBuffer;

typedef struct {
	void *dst;
	size_t size;
	size_t pos;
} ZSTD_outBuffer;

ZSTD_DStream *ZSTD_createDStream(void);
size_t ZSTD_freeDStream(ZSTD_DStream *zds);
size_t ZSTD_initDStream(ZSTD_DStream *zds);
size_t ZSTD_decompressStream(ZSTD_DStream *zds, ZSTD_outBuffer *output, ZSTD_inBuffer *input);
unsigned ZSTD_isError(size_t code);

#endif //BLASTEM_ZSTD_STUB_H_
