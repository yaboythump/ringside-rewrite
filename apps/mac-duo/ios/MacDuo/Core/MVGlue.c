/*
	MVGlue.c — Mini vMac platform glue for Mac Duo (iPhone).

	Based on Mini vMac's OSGLUERETRO.c / OSGLUSD2.c:
	Copyright (C) 2009 Michael Hanni, Christian Bauer,
	Stephan Kochen, Paul C. Pratt, and others.
	Mac Duo changes (plain stdio files, host-driven ticks, BGRA frames,
	lock-free sound ring, thread-safe input queue): Copyright (C) 2026
	CT Network Studios.

	You can redistribute this file and/or modify it under the terms
	of version 2 of the GNU General Public License as published by
	the Free Software Foundation. See vendor/minivmac/COPYING.txt.
*/

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/stat.h>

#include "CNFGRAPI.h"
#include "SYSDEPNS.h"
#include "ENDIANAC.h"
#include "MYOSGLUE.h"
#include "STRCONST.h"
#include "DATE2SEC.h"

#include "MVCore.h"

/* Emulator entry points from PROGMAIN.c (built with __LIBRETRO__ so they're global). */
void DoEmulateOneTick(void);
blnr InitEmulation(void);
void DoEmulateExtraTime(void);

/* --- some simple utilities --- */

GLOBALPROC MyMoveBytes(anyp srcPtr, anyp destPtr, si5b byteCount)
{
	(void) memmove((char *)destPtr, (char *)srcPtr, byteCount);
}

/* --- control mode and internationalization --- */

#define NeedCell2PlainAsciiMap 1
#include "INTLCHAR.h"

#define WriteExtraErr(s)

#include "COMOSGLU.h"
#include "CONTROLM.h"
#include "PROGMAIN.h"

/* --- state shared with Swift --- */

static pthread_mutex_t mv_lock = PTHREAD_MUTEX_INITIALIZER;
static atomic_int mv_state = MVStateNotStarted;
static atomic_uint_fast64_t mv_ticks = 0;
static char mv_message[256];

/* --- parameter buffers --- */

#if IncludePbufs
LOCALVAR void *PbufDat[NumPbufs];

LOCALFUNC tMacErr PbufNewFromPtr(void *p, ui5b count, tPbuf *r)
{
	tPbuf i;

	if (! FirstFreePbuf(&i)) {
		free(p);
		return mnvm_miscErr;
	}
	*r = i;
	PbufDat[i] = p;
	PbufNewNotify(i, count);
	return mnvm_noErr;
}

GLOBALFUNC tMacErr PbufNew(ui5b count, tPbuf *r)
{
	void *p = calloc(1, count);
	if (NULL == p) {
		return mnvm_miscErr;
	}
	return PbufNewFromPtr(p, count, r);
}

GLOBALPROC PbufDispose(tPbuf i)
{
	free(PbufDat[i]);
	PbufDisposeNotify(i);
}

GLOBALPROC PbufTransfer(ui3p Buffer,
	tPbuf i, ui5r offset, ui5r count, blnr IsWrite)
{
	void *p = ((ui3p)PbufDat[i]) + offset;
	if (IsWrite) {
		(void) memcpy(p, Buffer, count);
	} else {
		(void) memcpy(Buffer, p, count);
	}
}

/* Disk names shown by the Mac: plain ASCII is enough here. */
LOCALFUNC tMacErr NativeTextToMacRomanPbuf(const char *x, tPbuf *r)
{
	ui5b L = (ui5b)strlen(x);
	ui3p p = (ui3p)malloc(L ? L : 1);
	ui5b i;

	if (NULL == p) {
		return mnvm_miscErr;
	}
	for (i = 0; i < L; ++i) {
		ui3b v = (ui3b)x[i];
		p[i] = (v >= 128) ? '?' : ((10 == v) ? 13 : v);
	}
	return PbufNewFromPtr(p, L, r);
}
#endif

/* --- clipboard (not shared with iOS yet) --- */

#if IncludeHostTextClipExchange
GLOBALFUNC tMacErr HTCEexport(tPbuf i)
{
	PbufDispose(i);
	return mnvm_miscErr;
}

GLOBALFUNC tMacErr HTCEimport(tPbuf *r)
{
	(void) r;
	return mnvm_miscErr;
}
#endif

/* --- drives --- */

LOCALVAR FILE *Drives[NumDrives];
LOCALVAR char *DrivePaths[NumDrives];

GLOBALFUNC tMacErr vSonyTransfer(blnr IsWrite, ui3p Buffer,
	tDrive Drive_No, ui5r Sony_Start, ui5r Sony_Count,
	ui5r *Sony_ActCount)
{
	tMacErr err = mnvm_miscErr;
	FILE *f = Drives[Drive_No];
	ui5r done = 0;

	if (NULL != f && 0 == fseek(f, (long)Sony_Start, SEEK_SET)) {
		if (IsWrite) {
			done = (ui5r)fwrite(Buffer, 1, Sony_Count, f);
			fflush(f);
		} else {
			done = (ui5r)fread(Buffer, 1, Sony_Count, f);
		}
		if (done == Sony_Count) {
			err = mnvm_noErr;
		}
	}
	if (nullpr != Sony_ActCount) {
		*Sony_ActCount = done;
	}
	return err;
}

GLOBALFUNC tMacErr vSonyGetSize(tDrive Drive_No, ui5r *Sony_Count)
{
	FILE *f = Drives[Drive_No];
	long size;

	if (NULL == f || 0 != fseek(f, 0, SEEK_END)) {
		return mnvm_miscErr;
	}
	size = ftell(f);
	if (size < 0) {
		return mnvm_miscErr;
	}
	*Sony_Count = (ui5r)size;
	return mnvm_noErr;
}

LOCALFUNC tMacErr vSonyEject0(tDrive Drive_No, blnr deleteit)
{
	DiskEjectedNotify(Drive_No);
	if (NULL != Drives[Drive_No]) {
		fclose(Drives[Drive_No]);
		Drives[Drive_No] = NULL;
	}
	if (deleteit && NULL != DrivePaths[Drive_No]) {
		(void) remove(DrivePaths[Drive_No]);
	}
	free(DrivePaths[Drive_No]);
	DrivePaths[Drive_No] = NULL;
	return mnvm_noErr;
}

GLOBALFUNC tMacErr vSonyEject(tDrive Drive_No)
{
	return vSonyEject0(Drive_No, falseblnr);
}

#if IncludeSonyNew
GLOBALFUNC tMacErr vSonyEjectDelete(tDrive Drive_No)
{
	return vSonyEject0(Drive_No, trueblnr);
}
#endif

#if IncludeSonyGetName
GLOBALFUNC tMacErr vSonyGetName(tDrive Drive_No, tPbuf *r)
{
	const char *path = DrivePaths[Drive_No];
	const char *name;

	if (NULL == path) {
		return mnvm_miscErr;
	}
	name = strrchr(path, '/');
	return NativeTextToMacRomanPbuf(name ? name + 1 : path, r);
}
#endif

LOCALFUNC blnr Sony_InsertPath(const char *path)
{
	tDrive Drive_No;
	blnr locked = falseblnr;
	FILE *f;

	if (! FirstFreeDisk(&Drive_No)) {
		snprintf(mv_message, sizeof mv_message, "%s", kStrTooManyImagesTitle);
		return falseblnr;
	}
	f = fopen(path, "r+b");
	if (NULL == f) {
		locked = trueblnr;
		f = fopen(path, "rb");
	}
	if (NULL == f) {
		snprintf(mv_message, sizeof mv_message, "%s", kStrOpenFailTitle);
		return falseblnr;
	}
	Drives[Drive_No] = f;
	DrivePaths[Drive_No] = strdup(path);
	DiskInsertNotify(Drive_No, locked);
	return trueblnr;
}

#if IncludeSonyNew
/* "New Disk" from the Mac side isn't offered on iPhone. */
LOCALPROC MakeNewDiskAtDefault(ui5b L)
{
	(void) L;
}
#endif

/* --- ROM --- */

static uint32_t mv_rom_checksum(const uint8_t *rom, size_t size)
{
	uint32_t sum = 0;
	size_t i;
	for (i = 4; i + 1 < size; i += 2) {
		sum += ((uint32_t)rom[i] << 8) | rom[i + 1];
	}
	return sum;
}

static int mv_read_rom(const char *path, uint8_t *dst, long *size)
{
	FILE *f = fopen(path, "rb");
	long n;
	if (NULL == f) {
		return 0;
	}
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	*size = n;
	fseek(f, 0, SEEK_SET);
	if (n == kROM_Size && NULL != dst) {
		if (fread(dst, 1, kROM_Size, f) != kROM_Size) {
			*size = -1;
		}
	}
	fclose(f);
	return 1;
}

MVRomCheck MVCoreCheckROM(const char *path, uint32_t *checksum)
{
	static uint8_t buf[kROM_Size];
	long size = 0;
	uint32_t stored, sum;

	if (NULL != checksum) {
		*checksum = 0;
	}
	if (! mv_read_rom(path, buf, &size)) {
		return MVRomMissing;
	}
	if (size != kROM_Size) {
		return MVRomWrongSize;
	}
	stored = ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16)
		| ((uint32_t)buf[2] << 8) | buf[3];
	sum = mv_rom_checksum(buf, kROM_Size);
	if (NULL != checksum) {
		*checksum = stored;
	}
	if (stored != sum) {
		return MVRomBadChecksum;
	}
	if (sum == kRomCheckSum1 || sum == kRomCheckSum2) {
		return MVRomOK;
	}
	return MVRomUnknown;
}

/* --- video out --- */

static uint32_t mv_frames[2][vMacScreenWidth * vMacScreenHeight];
static int mv_front = 0;
static uint64_t mv_frame_no = 0;

static void mv_render(void)
{
	uint32_t *dst = mv_frames[1 - mv_front];
	ui3p src = GetCurDrawBuff();
	int i, n;

#if 0 != vMacScreenDepth
	if (UseColorMode) {
		uint32_t clut[CLUT_size];
		for (i = 0; i < CLUT_size; ++i) {
			clut[i] = 0xFF000000u
				| (((uint32_t)CLUT_reds[i] & 0xFF00) << 8)
				| ((uint32_t)CLUT_greens[i] & 0xFF00)
				| (((uint32_t)CLUT_blues[i] & 0xFF00) >> 8);
		}
		n = vMacScreenByteWidth * vMacScreenHeight;
		for (i = 0; i < n; ++i) {
			ui3b b = src[i];
#if 3 == vMacScreenDepth
			*dst++ = clut[b];
#elif 2 == vMacScreenDepth
			*dst++ = clut[b >> 4];
			*dst++ = clut[b & 0x0F];
#elif 1 == vMacScreenDepth
			*dst++ = clut[b >> 6];
			*dst++ = clut[(b >> 4) & 3];
			*dst++ = clut[(b >> 2) & 3];
			*dst++ = clut[b & 3];
#endif
		}
	} else
#endif
	{
		n = vMacScreenMonoByteWidth * vMacScreenHeight;
		for (i = 0; i < n; ++i) {
			ui3b b = src[i];
			int k;
			for (k = 7; k >= 0; --k) {
				*dst++ = ((b >> k) & 1) ? 0xFF000000u : 0xFFFFFFFFu;
			}
		}
	}

	pthread_mutex_lock(&mv_lock);
	mv_front = 1 - mv_front;
	++mv_frame_no;
	pthread_mutex_unlock(&mv_lock);
}

uint64_t MVCoreCopyFrame(uint32_t *dst, uint64_t lastFrame)
{
	uint64_t n;
	pthread_mutex_lock(&mv_lock);
	n = mv_frame_no;
	if (n != lastFrame && n != 0) {
		memcpy(dst, mv_frames[mv_front], sizeof mv_frames[0]);
	}
	pthread_mutex_unlock(&mv_lock);
	return n;
}

GLOBALOSGLUPROC DoneWithDrawingForTick(void)
{
}

GLOBALOSGLUPROC WaitForNextTick(void)
{
}

/* --- input queue (any thread -> emulation thread) --- */

enum { kInKey, kInMousePos, kInMouseButton, kInDisk, kInReset, kInInterrupt, kInRelease };

typedef struct {
	int kind;
	int a, b;
	char *path;
} MVInput;

#define kInputQueueSize 256
static MVInput mv_inputs[kInputQueueSize];
static int mv_input_count = 0;
static int mv_mouse_x = vMacScreenWidth / 2;
static int mv_mouse_y = vMacScreenHeight / 2;

static int mv_push(int kind, int a, int b, char *path)
{
	int ok = 0;
	pthread_mutex_lock(&mv_lock);
	if (kInMousePos == kind && mv_input_count > 0
		&& kInMousePos == mv_inputs[mv_input_count - 1].kind)
	{
		mv_inputs[mv_input_count - 1].a = a;
		mv_inputs[mv_input_count - 1].b = b;
		ok = 1;
	} else if (mv_input_count < kInputQueueSize) {
		MVInput *in = &mv_inputs[mv_input_count++];
		in->kind = kind;
		in->a = a;
		in->b = b;
		in->path = path;
		ok = 1;
	}
	if (kInMousePos == kind && ok) {
		mv_mouse_x = a;
		mv_mouse_y = b;
	}
	pthread_mutex_unlock(&mv_lock);
	if (! ok) {
		free(path);
	}
	return ok;
}

static void mv_drain_inputs(void)
{
	MVInput local[kInputQueueSize];
	int n, i;

	pthread_mutex_lock(&mv_lock);
	n = mv_input_count;
	memcpy(local, mv_inputs, sizeof(MVInput) * n);
	mv_input_count = 0;
	pthread_mutex_unlock(&mv_lock);

	for (i = 0; i < n; ++i) {
		MVInput *in = &local[i];
		switch (in->kind) {
			case kInKey:
				if (in->a >= 0 && in->a < 128 && MKC_CM != in->a) {
					Keyboard_UpdateKeyMap2((ui3r)in->a, in->b ? trueblnr : falseblnr);
				}
				break;
			case kInMousePos:
				MyMousePositionSet((ui4r)in->a, (ui4r)in->b);
				break;
			case kInMouseButton:
				MyMouseButtonSet(in->a ? trueblnr : falseblnr);
				break;
			case kInDisk:
				(void) Sony_InsertPath(in->path);
				free(in->path);
				break;
			case kInReset:
				ForceMacOff = falseblnr;
				WantMacReset = trueblnr;
				break;
			case kInInterrupt:
				WantMacInterrupt = trueblnr;
				break;
			case kInRelease:
				DisconnectKeyCodes(0);
				MyMouseButtonSet(falseblnr);
				break;
		}
	}
}

static int mv_clamp(int v, int lo, int hi)
{
	return v < lo ? lo : (v > hi ? hi : v);
}

void MVCoreMouseSet(int x, int y)
{
	(void) mv_push(kInMousePos,
		mv_clamp(x, 0, vMacScreenWidth - 1),
		mv_clamp(y, 0, vMacScreenHeight - 1), NULL);
}

void MVCoreMouseButton(int down)
{
	(void) mv_push(kInMouseButton, down ? 1 : 0, 0, NULL);
}

void MVCoreMousePosition(int *x, int *y)
{
	pthread_mutex_lock(&mv_lock);
	*x = mv_mouse_x;
	*y = mv_mouse_y;
	pthread_mutex_unlock(&mv_lock);
}

void MVCoreKey(int macKey, int down)
{
	(void) mv_push(kInKey, macKey, down ? 1 : 0, NULL);
}

void MVCoreReleaseAll(void)
{
	(void) mv_push(kInRelease, 0, 0, NULL);
}

void MVCoreReset(void)
{
	/* Queued first so the emulation thread clears ForceMacOff itself. */
	if (mv_push(kInReset, 0, 0, NULL)
		&& MVStatePoweredOff == atomic_load(&mv_state))
	{
		atomic_store(&mv_state, MVStateRunning);
	}
}

void MVCoreInterrupt(void)
{
	(void) mv_push(kInInterrupt, 0, 0, NULL);
}

int MVCoreInsertDisk(const char *path)
{
	char *copy;
	if (NULL == path) {
		return 0;
	}
	copy = strdup(path);
	return copy ? mv_push(kInDisk, 0, 0, copy) : 0;
}

int MVCoreDiskCount(void)
{
	int i, n = 0;
	pthread_mutex_lock(&mv_lock);
	for (i = 0; i < NumDrives; ++i) {
		if (NULL != DrivePaths[i]) {
			++n;
		}
	}
	pthread_mutex_unlock(&mv_lock);
	return n;
}

int MVCoreDiskPath(int index, char *buf, int bufSize)
{
	int i, n = 0, found = 0;
	pthread_mutex_lock(&mv_lock);
	for (i = 0; i < NumDrives; ++i) {
		if (NULL != DrivePaths[i]) {
			if (n == index) {
				snprintf(buf, bufSize, "%s", DrivePaths[i]);
				found = 1;
				break;
			}
			++n;
		}
	}
	pthread_mutex_unlock(&mv_lock);
	return found;
}

/* --- time, date, location --- */

static struct timespec mv_extra_deadline;

static void mv_now(struct timespec *t)
{
	clock_gettime(CLOCK_MONOTONIC, t);
}

GLOBALFUNC blnr ExtraTimeNotOver(void)
{
	struct timespec t;
	mv_now(&t);
	if (t.tv_sec != mv_extra_deadline.tv_sec) {
		return t.tv_sec < mv_extra_deadline.tv_sec;
	}
	return t.tv_nsec < mv_extra_deadline.tv_nsec;
}

static void mv_update_date(void)
{
	time_t now = time(NULL);
	struct tm local;
	localtime_r(&now, &local);
	CurMacDateInSeconds = Date2MacSeconds(local.tm_sec, local.tm_min,
		local.tm_hour, local.tm_mday, 1 + local.tm_mon, 1900 + local.tm_year);
#if AutoTimeZone
	{
		long gmt = (long)local.tm_gmtoff;
		CurMacDelta = ((ui5b)gmt & 0x00FFFFFF)
			| ((local.tm_isdst ? 0x80 : 0) << 24);
	}
#endif
}

/* --- sound --- */

#if MySoundEnabled

#define kStageLen 1024
static ui3b mv_stage[kStageLen];

#define kRingLen 4096 /* power of two, ~0.18 s: keeps sound close to the picture */
static float mv_ring[kRingLen];
static atomic_uint mv_ring_write = 0;
static atomic_uint mv_ring_read = 0;

GLOBALFUNC tpSoundSamp MySound_BeginWrite(ui4r n, ui4r *actL)
{
	*actL = (n > kStageLen) ? kStageLen : n;
	return mv_stage;
}

GLOBALPROC MySound_EndWrite(ui4r actL)
{
	unsigned w = atomic_load_explicit(&mv_ring_write, memory_order_relaxed);
	unsigned r = atomic_load_explicit(&mv_ring_read, memory_order_acquire);
	ui4r i;

	for (i = 0; i < actL; ++i) {
		if (w - r >= kRingLen) {
			break; /* the speaker is behind; drop the rest */
		}
		mv_ring[w & (kRingLen - 1)] = ((float)mv_stage[i] - 128.0f) * (1.0f / 128.0f) * 0.7f;
		++w;
	}
	atomic_store_explicit(&mv_ring_write, w, memory_order_release);
}

int MVCoreReadAudio(float *left, float *right, int frames)
{
	unsigned r = atomic_load_explicit(&mv_ring_read, memory_order_relaxed);
	unsigned w = atomic_load_explicit(&mv_ring_write, memory_order_acquire);
	int i, got = 0;

	for (i = 0; i < frames; ++i) {
		float v = 0.0f;
		if (r != w) {
			v = mv_ring[r & (kRingLen - 1)];
			++r;
			++got;
		}
		left[i] = v;
		right[i] = v;
	}
	atomic_store_explicit(&mv_ring_read, r, memory_order_release);
	return got;
}

#else

int MVCoreReadAudio(float *left, float *right, int frames)
{
	memset(left, 0, sizeof(float) * frames);
	memset(right, 0, sizeof(float) * frames);
	return 0;
}

#endif

/* --- messages --- */

int MVCoreTakeMessage(char *buf, int bufSize)
{
	int have;
	pthread_mutex_lock(&mv_lock);
	if ('\0' == mv_message[0] && nullpr != SavedBriefMsg) {
		/* Mini vMac strings use ";[" style escapes; titles are plain. */
		snprintf(mv_message, sizeof mv_message, "%s", SavedBriefMsg);
		SavedBriefMsg = nullpr;
	}
	have = ('\0' != mv_message[0]);
	if (have) {
		snprintf(buf, bufSize, "%s", mv_message);
		mv_message[0] = '\0';
	}
	pthread_mutex_unlock(&mv_lock);
	return have;
}

/* --- memory --- */

LOCALPROC ReserveAllocAll(void)
{
	ReserveAllocOneBlock(&ROM, kROM_Size, 5, falseblnr);
	ReserveAllocOneBlock(&screencomparebuff, vMacScreenNumBytes, 5, trueblnr);
#if UseControlKeys
	ReserveAllocOneBlock(&CntrlDisplayBuff, vMacScreenNumBytes, 5, falseblnr);
#endif
	EmulationReserveAlloc();
}

LOCALFUNC blnr AllocMyMemory(void)
{
	uimr n;

	ReserveAllocOffset = 0;
	ReserveAllocBigBlock = nullpr;
	ReserveAllocAll();
	n = ReserveAllocOffset;
	ReserveAllocBigBlock = (ui3p)calloc(1, n);
	if (NULL == ReserveAllocBigBlock) {
		return falseblnr;
	}
	ReserveAllocOffset = 0;
	ReserveAllocAll();
	return n == ReserveAllocOffset;
}

/* --- main program flow --- */

int MVCoreStart(const char *romPath)
{
	long size = 0;
	MVRomCheck check;

	if (MVStateNotStarted != atomic_load(&mv_state)) {
		return MVStateRunning == atomic_load(&mv_state)
			|| MVStatePoweredOff == atomic_load(&mv_state);
	}
	check = MVCoreCheckROM(romPath, NULL);
	if (MVRomOK != check && MVRomUnknown != check) {
		snprintf(mv_message, sizeof mv_message, "%s",
			MVRomMissing == check ? kStrNoROMTitle
			: MVRomWrongSize == check ? kStrShortROMTitle : kStrCorruptedROMTitle);
		return 0;
	}
	if (! AllocMyMemory()) {
		snprintf(mv_message, sizeof mv_message, "%s", kStrOutOfMemTitle);
		atomic_store(&mv_state, MVStateFailed);
		return 0;
	}
	if (! mv_read_rom(romPath, ROM, &size) || size != kROM_Size) {
		snprintf(mv_message, sizeof mv_message, "%s", kStrNoReadROMTitle);
		atomic_store(&mv_state, MVStateFailed);
		return 0;
	}
	ROM_loaded = trueblnr;
	SpeedStopped = falseblnr;
	ColorModeWorks = trueblnr;
	InitKeyCodes();
	mv_update_date();
	if (! InitEmulation()) {
		snprintf(mv_message, sizeof mv_message, "%s", kStrNoReadROMTitle);
		atomic_store(&mv_state, MVStateFailed);
		return 0;
	}
	atomic_store(&mv_state, MVStateRunning);
	return 1;
}

MVState MVCoreGetState(void)
{
	return (MVState)atomic_load(&mv_state);
}

void MVCoreSetSpeed(int speed)
{
	pthread_mutex_lock(&mv_lock);
	SpeedValue = (speed < 0) ? (ui3b)-1 : (ui3b)(speed > 5 ? 5 : speed);
	pthread_mutex_unlock(&mv_lock);
}

uint64_t MVCoreTickCount(void)
{
	return atomic_load(&mv_ticks);
}

void MVCoreRunTick(int budgetMicros)
{
	static int tick_in_second = 0;
	struct timespec t;
	long ns;

	if (MVStateRunning != atomic_load(&mv_state)) {
		return;
	}

	mv_drain_inputs();

	if (++tick_in_second >= 60) {
		tick_in_second = 0;
		mv_update_date();
	}

	++OnTrueTime;
	DoEmulateOneTick();

	mv_now(&t);
	ns = t.tv_nsec + (long)(budgetMicros < 0 ? 0 : budgetMicros) * 1000L;
	mv_extra_deadline.tv_sec = t.tv_sec + ns / 1000000000L;
	mv_extra_deadline.tv_nsec = ns % 1000000000L;
	if (0 != SpeedValue) {
		DoEmulateExtraTime();
	}

	mv_render();
	ScreenClearChanges();
	atomic_fetch_add(&mv_ticks, 1);

	if (ForceMacOff) {
		atomic_store(&mv_state, MVStatePoweredOff);
	}
}
