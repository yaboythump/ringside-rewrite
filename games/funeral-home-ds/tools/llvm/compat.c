// Small runtime helpers that GCC's libgcc provides on the DS but LLVM's
// compiler-rt does not for ARMv4T/ARMv5TE (no LDREX/STREX on these CPUs).
// The DS CPUs are single-core each, so word-sized aligned accesses are atomic,
// and read-modify-write sequences only need interrupts masked.
#include <stdint.h>
#include <stdbool.h>

void __sync_synchronize_none(void) {}

static inline uint32_t irq_off(void) {
    volatile uint32_t *ime = (volatile uint32_t *)0x04000208;
    uint32_t old = *ime; *ime = 0; return old;
}
static inline void irq_restore(uint32_t old) { *(volatile uint32_t *)0x04000208 = old; }

#define LOADSTORE(N, T) \
T __atomic_load_##N(const volatile void *p, int m) { (void)m; return *(const volatile T *)p; } \
void __atomic_store_##N(volatile void *p, T v, int m) { (void)m; *(volatile T *)p = v; } \
T __atomic_exchange_##N(volatile void *p, T v, int m) { (void)m; uint32_t s = irq_off(); T o = *(volatile T *)p; *(volatile T *)p = v; irq_restore(s); return o; } \
bool __atomic_compare_exchange_##N(volatile void *p, void *e, T d, bool w, int a, int b) { (void)w; (void)a; (void)b; \
    uint32_t s = irq_off(); T c = *(volatile T *)p; bool ok = c == *(T *)e; if (ok) *(volatile T *)p = d; else *(T *)e = c; irq_restore(s); return ok; } \
T __atomic_fetch_add_##N(volatile void *p, T v, int m) { (void)m; uint32_t s = irq_off(); T o = *(volatile T *)p; *(volatile T *)p = o + v; irq_restore(s); return o; } \
T __atomic_fetch_sub_##N(volatile void *p, T v, int m) { (void)m; uint32_t s = irq_off(); T o = *(volatile T *)p; *(volatile T *)p = o - v; irq_restore(s); return o; } \
T __atomic_fetch_and_##N(volatile void *p, T v, int m) { (void)m; uint32_t s = irq_off(); T o = *(volatile T *)p; *(volatile T *)p = o & v; irq_restore(s); return o; } \
T __atomic_fetch_or_##N(volatile void *p, T v, int m) { (void)m; uint32_t s = irq_off(); T o = *(volatile T *)p; *(volatile T *)p = o | v; irq_restore(s); return o; }

LOADSTORE(1, uint8_t)
LOADSTORE(2, uint16_t)
LOADSTORE(4, uint32_t)
