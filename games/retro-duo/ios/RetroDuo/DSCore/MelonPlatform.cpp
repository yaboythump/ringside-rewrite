// Retro Duo - the platform layer melonDS needs: files, threads, locks, time and callbacks.
// Copyright 2026 CT Network Studios. Licensed under the GNU GPL v3 or later (see LICENSE).
// Retro Duo runs without network play, camera, microphone or DSi features, so those are stubs.
#include "Platform.h"

#include <chrono>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <sys/stat.h>
#include <unistd.h>

void RetroDuoMarkSaveChanged(void *userdata);

namespace melonDS::Platform {

struct FileHandle { FILE *file; };
struct Thread { std::thread thread; };
struct Semaphore {
    std::mutex lock;
    std::condition_variable signal;
    int count = 0;
};
struct Mutex { std::mutex lock; };

void SignalStop(StopReason, void *) {}

std::string GetLocalFilePath(const std::string &filename) {
    // melonDS only asks for local files for optional extras (DLDI images, Wi-Fi settings).
    const char *tmp = getenv("TMPDIR");
    std::string dir = tmp ? tmp : "/tmp";
    if (!dir.empty() && dir.back() != '/') dir += '/';
    return dir + filename;
}

static const char *modeString(FileMode mode, bool exists) {
    bool read = mode & FileMode::Read, write = mode & FileMode::Write;
    bool text = mode & FileMode::Text;
    if (mode & FileMode::Append) return text ? "a+" : "a+b";
    if (read && write) {
        if ((mode & FileMode::Preserve) && exists) return text ? "r+" : "r+b";
        return text ? "w+" : "w+b";
    }
    if (write) return text ? "w" : "wb";
    return text ? "r" : "rb";
}

FileHandle *OpenFile(const std::string &path, FileMode mode) {
    struct stat info;
    bool exists = stat(path.c_str(), &info) == 0;
    if ((mode & FileMode::NoCreate) && !exists) return nullptr;
    if (!(mode & FileMode::Write) && !exists) return nullptr;
    FILE *file = fopen(path.c_str(), modeString(mode, exists));
    return file ? new FileHandle{file} : nullptr;
}

FileHandle *OpenLocalFile(const std::string &path, FileMode mode) {
    return OpenFile(path.empty() || path[0] == '/' ? path : GetLocalFilePath(path), mode);
}

bool FileExists(const std::string &name) {
    struct stat info;
    return stat(name.c_str(), &info) == 0;
}

bool LocalFileExists(const std::string &name) { return FileExists(GetLocalFilePath(name)); }
bool CheckFileWritable(const std::string &path) { return access(path.c_str(), W_OK) == 0 || !FileExists(path); }
bool CheckLocalFileWritable(const std::string &path) { return CheckFileWritable(GetLocalFilePath(path)); }

bool CloseFile(FileHandle *file) {
    if (!file) return false;
    bool ok = fclose(file->file) == 0;
    delete file;
    return ok;
}

bool IsEndOfFile(FileHandle *file) { return feof(file->file) != 0; }
bool FileReadLine(char *str, int count, FileHandle *file) { return fgets(str, count, file->file) != nullptr; }
u64 FilePosition(FileHandle *file) { return (u64)ftello(file->file); }

bool FileSeek(FileHandle *file, s64 offset, FileSeekOrigin origin) {
    int whence = origin == FileSeekOrigin::Start ? SEEK_SET : origin == FileSeekOrigin::Current ? SEEK_CUR : SEEK_END;
    return fseeko(file->file, offset, whence) == 0;
}

void FileRewind(FileHandle *file) { rewind(file->file); }
u64 FileRead(void *data, u64 size, u64 count, FileHandle *file) { return fread(data, size, count, file->file); }
bool FileFlush(FileHandle *file) { return fflush(file->file) == 0; }
u64 FileWrite(const void *data, u64 size, u64 count, FileHandle *file) { return fwrite(data, size, count, file->file); }

u64 FileWriteFormatted(FileHandle *file, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int written = vfprintf(file->file, fmt, args);
    va_end(args);
    return written < 0 ? 0 : (u64)written;
}

u64 FileLength(FileHandle *file) {
    off_t position = ftello(file->file);
    fseeko(file->file, 0, SEEK_END);
    off_t length = ftello(file->file);
    fseeko(file->file, position, SEEK_SET);
    return (u64)length;
}

void Log(LogLevel level, const char *fmt, ...) {
#ifdef RETRO_DUO_VERBOSE
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
#else
    (void)level; (void)fmt;
#endif
}

Thread *Thread_Create(std::function<void()> func) { return new Thread{std::thread(std::move(func))}; }
void Thread_Free(Thread *thread) {
    if (!thread) return;
    if (thread->thread.joinable()) thread->thread.detach();
    delete thread;
}
void Thread_Wait(Thread *thread) {
    if (thread && thread->thread.joinable()) thread->thread.join();
}

Semaphore *Semaphore_Create() { return new Semaphore(); }
void Semaphore_Free(Semaphore *sema) { delete sema; }
void Semaphore_Reset(Semaphore *sema) {
    std::lock_guard<std::mutex> lock(sema->lock);
    sema->count = 0;
}
void Semaphore_Wait(Semaphore *sema) {
    std::unique_lock<std::mutex> lock(sema->lock);
    sema->signal.wait(lock, [sema] { return sema->count > 0; });
    sema->count--;
}
bool Semaphore_TryWait(Semaphore *sema, int timeout_ms) {
    std::unique_lock<std::mutex> lock(sema->lock);
    if (timeout_ms <= 0) {
        if (sema->count <= 0) return false;
    } else if (!sema->signal.wait_for(lock, std::chrono::milliseconds(timeout_ms), [sema] { return sema->count > 0; })) {
        return false;
    }
    sema->count--;
    return true;
}
void Semaphore_Post(Semaphore *sema, int count) {
    {
        std::lock_guard<std::mutex> lock(sema->lock);
        sema->count += count;
    }
    sema->signal.notify_all();
}

Mutex *Mutex_Create() { return new Mutex(); }
void Mutex_Free(Mutex *mutex) { delete mutex; }
void Mutex_Lock(Mutex *mutex) { mutex->lock.lock(); }
void Mutex_Unlock(Mutex *mutex) { mutex->lock.unlock(); }
bool Mutex_TryLock(Mutex *mutex) { return mutex->lock.try_lock(); }

void Sleep(u64 usecs) { std::this_thread::sleep_for(std::chrono::microseconds(usecs)); }

u64 GetMSCount() {
    using namespace std::chrono;
    return (u64)duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

u64 GetUSCount() {
    using namespace std::chrono;
    return (u64)duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

void WriteNDSSave(const u8 *, u32, u32, u32, void *userdata) { RetroDuoMarkSaveChanged(userdata); }
void WriteGBASave(const u8 *, u32, u32, u32, void *) {}
void WriteFirmware(const Firmware &, u32, u32, void *) {}
void WriteDateTime(int, int, int, int, int, int, void *) {}

void MP_Begin(void *) {}
void MP_End(void *) {}
int MP_SendPacket(u8 *, int, u64, void *) { return 0; }
int MP_RecvPacket(u8 *, u64 *, void *) { return 0; }
int MP_SendCmd(u8 *, int, u64, void *) { return 0; }
int MP_SendReply(u8 *, int, u64, u16, void *) { return 0; }
int MP_SendAck(u8 *, int, u64, void *) { return 0; }
int MP_RecvHostPacket(u8 *, u64 *, void *) { return 0; }
u16 MP_RecvReplies(u8 *, u64, u16, void *) { return 0; }

int Net_SendPacket(u8 *, int, void *) { return 0; }
int Net_RecvPacket(u8 *, void *) { return 0; }

void Camera_Start(int, void *) {}
void Camera_Stop(int, void *) {}
void Camera_CaptureFrame(int, u32 *, int, int, bool, void *) {}

void Mic_Start(void *) {}
void Mic_Stop(void *) {}
int Mic_ReadInput(s16 *, int, void *) { return 0; }

AACDecoder *AAC_Init() { return nullptr; }
void AAC_DeInit(AACDecoder *) {}
bool AAC_Configure(AACDecoder *, int, int) { return false; }
bool AAC_DecodeFrame(AACDecoder *, const void *, int, void *, int) { return false; }

bool Addon_KeyDown(KeyType, void *) { return false; }
void Addon_RumbleStart(u32, void *) {}
void Addon_RumbleStop(void *) {}
float Addon_MotionQuery(MotionQueryType, void *) { return 0; }

DynamicLibrary *DynamicLibrary_Load(const char *) { return nullptr; }
void DynamicLibrary_Unload(DynamicLibrary *) {}
void *DynamicLibrary_LoadFunction(DynamicLibrary *, const char *) { return nullptr; }

} // namespace melonDS::Platform
