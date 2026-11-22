//See zstd.h in this directory for why this exists.

#include "zstd.h"

ZSTD_DStream *ZSTD_createDStream(void)
{
	//libchdr treats a null stream as a failed codec init, which is what makes
	//chd_open() reject a zstd compressed CHD rather than misread it.
	return 0;
}

size_t ZSTD_freeDStream(ZSTD_DStream *zds)
{
	return 0;
}

size_t ZSTD_initDStream(ZSTD_DStream *zds)
{
	//Any value ZSTD_isError() calls an error. libchdr only ever compares against
	//that, so the exact code does not matter as long as it is one.
	return (size_t)-1;
}

size_t ZSTD_decompressStream(ZSTD_DStream *zds, ZSTD_outBuffer *output, ZSTD_inBuffer *input)
{
	return (size_t)-1;
}

unsigned ZSTD_isError(size_t code)
{
	//Real zstd reserves the top 128 values as error codes.
	return code > (size_t)-128;
}
