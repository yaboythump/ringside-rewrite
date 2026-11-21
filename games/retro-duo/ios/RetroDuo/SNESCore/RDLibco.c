// libco (bsnes's coroutine library) for Retro Duo.
//
// On 64-bit ARM (iPhone), libco's own aarch64.c keeps its context switch as machine code
// in a data array and makes that page executable with mprotect at run time, which iOS
// does not allow. This file has the same instructions, the same register layout and the
// same API, but as a normal compiled function. Everywhere else (the Linux test machines)
// it uses libco's stock implementation unchanged.
#include "SNESConfig.h"

#if defined(__aarch64__)

#define LIBCO_C
#include "libco/libco.h"
#include "libco/settings.h"

#include <stdlib.h>

static thread_local unsigned long co_active_buffer[64];
static thread_local cothread_t co_active_handle = 0;

/* co_swap(to = x0, from = x1): save callee-saved registers, sp and lr into `from`,
   load them from `to`, then jump to the saved lr. Mirrors libco/aarch64.c exactly. */
__attribute__((naked)) static void co_swap(cothread_t to, cothread_t from) {
    __asm__ volatile(
        "stp x8, x9, [x1]\n"
        "stp x10, x11, [x1, #16]\n"
        "stp x12, x13, [x1, #32]\n"
        "stp x14, x15, [x1, #48]\n"
        "str x19, [x1, #72]\n"
        "stp x20, x21, [x1, #80]\n"
        "stp x22, x23, [x1, #96]\n"
        "stp x24, x25, [x1, #112]\n"
        "stp x26, x27, [x1, #128]\n"
        "stp x28, x29, [x1, #144]\n"
        "mov x16, sp\n"
        "stp x16, x30, [x1, #160]\n"
        "ldp x8, x9, [x0]\n"
        "ldp x10, x11, [x0, #16]\n"
        "ldp x12, x13, [x0, #32]\n"
        "ldp x14, x15, [x0, #48]\n"
        "ldr x19, [x0, #72]\n"
        "ldp x20, x21, [x0, #80]\n"
        "ldp x22, x23, [x0, #96]\n"
        "ldp x24, x25, [x0, #112]\n"
        "ldp x26, x27, [x0, #128]\n"
        "ldp x28, x29, [x0, #144]\n"
        "ldp x16, x17, [x0, #160]\n"
        "mov sp, x16\n"
        "br x17\n");
}

cothread_t co_active(void) {
    if (!co_active_handle) co_active_handle = &co_active_buffer;
    return co_active_handle;
}

cothread_t co_derive(void *memory, unsigned int size, void (*entrypoint)(void)) {
    unsigned long *handle;
    if (!co_active_handle) co_active_handle = &co_active_buffer;
    if ((handle = (unsigned long *)memory)) {
        unsigned int offset = (size & ~15);
        unsigned long *p = (unsigned long *)((unsigned char *)handle + offset);
        handle[19] = (unsigned long)p;          /* x29 (frame pointer) */
        handle[20] = (unsigned long)p;          /* stack pointer */
        handle[21] = (unsigned long)entrypoint; /* link register */
    }
    return handle;
}

cothread_t co_create(unsigned int size, void (*entrypoint)(void)) {
    void *memory = malloc(size);
    if (!memory) return (cothread_t)0;
    return co_derive(memory, size, entrypoint);
}

void co_delete(cothread_t handle) { free(handle); }

void co_switch(cothread_t handle) {
    cothread_t previous = co_active_handle;
    co_swap(co_active_handle = handle, previous);
}

int co_serializable(void) { return 1; }

#else
#include "libco/libco.c"
#endif
