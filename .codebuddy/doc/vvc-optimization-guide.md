# VVC Decoder Optimization Guide

**Based on:** 10-bit performance analysis (500 frames per test)  
**Platforms:** ARM64 (Pi5, Android), x86_64 (black2)

---

## Executive Summary

### Key Finding: 10-bit is the Primary Bottleneck

10-bit VVC decoding shows significantly different characteristics than 8-bit:
- **2x memory bandwidth** requirement
- **ALF filter** is #1 hotspot on fast ARM (Android: 18%)
- **Deblocking** remains unoptimized (C code) on all platforms

### Performance Summary

| Platform | 10-bit 1080p | Memory % | Sync % | Critical Bottleneck |
|----------|--------------|----------|--------|---------------------|
| ARM (Pi5, 4T) | 32 fps | 17.9% | 1.0% | memcpy + ALF |
| **Android (4T)** | **70 fps** | **9.1%** | **1.5%** | **ALF cache (18%)** |
| x86 (8T) | 214 fps | 11.8% | 2.5% | deblocking (C) |

**Key Insight:** Android is 2.2x faster than Pi5 due to better memory subsystem, but this reveals ALF as the #1 bottleneck.

---

## Cross-Platform Comparison

### Architecture-Level Bottlenecks

| Bottleneck | Pi5 | Android | x86 | Notes |
|------------|-----|---------|-----|-------|
| **Memory Operations** | 17.9% | **9.1%** | 11.8% | Android SoC has best memory subsystem |
| **ALF Filter** | 12.0% | **18.0%** | 4.0% | Revealed at higher performance |
| **Deblocking** | 12.0% | 11.0% | 11.0% | All need SIMD for 10-bit |
| **Task Scheduling** | 1.0% | 1.5% | 2.5% | Scales with thread count |
| **Entropy Coding** | 3.4% | 4.0% | 5.8% | x86 shows higher parsing overhead |

### Hot Function Comparison (city_crowd 10-bit)

| Function | Pi5 % | Android % | x86 % | Key Insight |
|----------|-------|-----------|-------|-------------|
| memcpy/memset | 17.9% | **9.1%** | 11.8% | Android uses SIMD-accelerated libc |
| ALF filter | 12.0% | **18.0%** | 4.0% | **Cache issue on fast ARM** |
| Deblocking | 12.0% | 11.0% | 11.0% | Consistent C code overhead |
| Motion Comp | 8.5% | 10.0% | 5.0% | Variable NEON coverage |

---

## Prioritized Optimization Recommendations

### P0: Critical - Maximum Impact

#### 1. Zero-Copy Pipeline (ARM: +20%, x86: +10%)

**Problem:** 17.9% (ARM) / 11.8% (x86) cycles in memcpy/memset

**Root Cause:** 
- Buffer copies between 9 CTU pipeline stages
- 10-bit samples amplify memory pressure (2x bandwidth)

**Solution:**
```c
// Current: copy between stages
void sao_filter_ctu(SAOContext *sao, uint8_t *src, uint8_t *dst) {
    memcpy(dst, src, size);  // ← Eliminate this
    apply_sao(dst);
}

// Optimized: in-place with ring buffer
typedef struct RingBuffer {
    uint8_t *buffers[3];  // Triple buffering
    int write_idx;
} RingBuffer;

void sao_filter_ctu(SAOContext *sao, RingBuffer *rb) {
    uint8_t *buf = rb->buffers[rb->write_idx];
    apply_sao(buf);
    rb->write_idx = (rb->write_idx + 1) % 3;
}
```

**Effort:** High (2-3 weeks)  
**Risk:** Medium (memory corruption bugs)  
**Validation:** Measure memcpy before/after with perf

---

#### 2. ALF Filter Cache Optimization (ARM: +15%, Android: +20%)

**Problem:** ALF is #2 hotspot on Pi5 (12.0%), **#1 on Android (18.0%)** despite NEON implementation

**Root Cause:**
- Memory access patterns not cache-optimal (revealed at higher performance)
- Classification overhead (2.8% on Android)
- Row-major access causes cache misses

**Solution:**
```c
// Current: row-by-row access
for (y = 0; y < height; y++) {
    for (x = 0; x < width; x += 8) {
        // Load 8x8 block, poor locality
        uint8x8_t p0 = vld1_u8(src + (y-3) * stride + x);
        ...
    }
}

// Optimized: 4x4 tile processing with prefetch
for (ty = 0; ty < height; ty += 4) {
    __builtin_prefetch(src + (ty+4) * stride);  // Prefetch next tile
    for (tx = 0; tx < width; tx += 4) {
        // Process 4x4 tile with high locality
        alf_filter_4x4_neon(src + ty * stride + tx, ...);
    }
}
```

**Effort:** Medium (1 week)  
**Risk:** Low  
**Validation:** Validate PSNR matches reference

---

### P1: High Impact

#### 3. AVX2 Deblocking Filter for 10-bit (x86: +15%, ARM: +10%)

**Problem:** Deblocking uses C code for 10-bit (11% total on both platforms)

**Current State:**
- 8-bit has SSE/AVX2 implementations
- 10-bit path falls back to C

**Solution:**
```c
// lib/libavcodec/x86/vvc_deblock.asm
; Add 10-bit AVX2 implementation
INIT_YMM avx2
%if BIT_DEPTH == 10
cglobal vvc_deblock_luma_10, 6, 6, 16, pix, stride, tc, no_p, no_q, max_len
    ; Load 8 pixels (16-bit each for 10-bit)
    vmovdqu ymm0, [pixq - 8]    ; p3-p0
    vmovdqu ymm1, [pixq]        ; q0-q3
    
    ; Compute filter decision (vectorized)
    vpabsw ymm2, ymm0, ymm1     ; abs(p - q)
    vpcmpgtw ymm3, ymm2, tc     ; compare with tc
    
    ; Apply filter (vectorized)
    ...
    
    RET
%endif
```

**Effort:** Medium (1-2 weeks)  
**Risk:** Low (existing 8-bit template)  
**Validation:** Compare output with C reference

---

#### 4. Work-Stealing Task Queues (x86: +10%, ARM: +5%)

**Problem:** Global executor lock causes 2.5% overhead at 8 threads (x86)

**Root Cause:**
```c
// Current: global lock
static int executor_worker_task(FFExecutor *e) {
    pthread_mutex_lock(&e->lock);  // ← Contention point
    task = get_ready_task(e);
    pthread_mutex_unlock(&e->lock);
    execute(task);
}
```

**Solution:** Lock-free work-stealing deque per thread
```c
typedef struct WorkStealingQueue {
    atomic_int top, bottom;
    VVCTask *tasks[MAX_TASKS];
} WSQueue;

// Push: lock-free
void ws_push(WSQueue *q, VVCTask *task) {
    int b = atomic_load(&q->bottom);
    q->tasks[b & MASK] = task;
    atomic_store(&q->bottom, b + 1);
}

// Steal: lock-free from other threads
VVCTask *ws_steal(WSQueue *q) {
    int t = atomic_load(&q->top);
    int b = atomic_load(&q->bottom);
    if (t >= b) return NULL;  // Empty
    VVCTask *task = q->tasks[t & MASK];
    if (atomic_compare_exchange(&q->top, t, t + 1)) {
        return task;
    }
    return NULL;  // Contention, retry elsewhere
}
```

**Effort:** High (2-3 weeks)  
**Risk:** High (concurrency bugs)  
**Validation:** Stress test with 16+ threads

---

#### 5. Batch Task Submission (x86: +5%, ARM: +3%)

**Problem:** One lock per task submission

**Solution:**
```c
// Current: one lock per task
for (int i = 0; i < num_tasks; i++) {
    pthread_mutex_lock(&executor->lock);
    add_task(executor, tasks[i]);  // N lock acquisitions
    pthread_mutex_unlock(&executor->lock);
}

// Optimized: batch with single lock
pthread_mutex_lock(&executor->lock);
for (int i = 0; i < num_tasks; i++) {
    add_task_nolock(executor, tasks[i]);  // 1 lock acquisition
}
pthread_cond_broadcast(&executor->cond);
pthread_mutex_unlock(&executor->lock);
```

**Effort:** Low (2-3 days)  
**Risk:** Low  
**Validation:** Measure lock contention with perf

---

### P2: Medium Impact

#### 6. NEON Luma Deblocking (ARM: +8%)

Similar to AVX2 deblocking but for ARM:
- Port 8-bit NEON implementation to 10-bit
- Focus on `vvc_loop_filter_luma_10`

**Effort:** Medium (1 week)  
**Risk:** Low

---

#### 7. Optimized Buffer Clearing (ARM: +5%)

**Problem:** 3.1% in `__memset_zva64` (ARM)

**Solution:** Use DC ZVA (Data Cache Zero by VA) for large buffers
```c
// Clear CTU buffers using DC ZVA
void clear_ctu_buffer_neon(uint8_t *buf, size_t size) {
    // DC ZVA zeros 64 bytes at a time
    asm volatile(
        "dc zva, %0"
        :: "r"(buf)
    );
}
```

**Effort:** Low (2 days)  
**Risk:** Low

---

### Android-Specific Optimizations

#### 8. big.LITTLE Task Affinity (Android: +10%)

**Problem:** Critical tasks may run on LITTLE cores

**Solution:** Bind ALF/deblocking to big cores
```c
// Bind compute-intensive tasks to big cores
void compute_intensive_task(VVCTask *task) {
    #ifdef __ANDROID__
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    // Big cores typically CPU 4-7 on Pixel Tensor G3
    for (int i = 4; i < 8; i++) {
        CPU_SET(i, &cpuset);
    }
    sched_setaffinity(0, sizeof(cpuset), &cpuset);
    #endif
    
    alf_filter_luma(...);
}
```

**Effort:** Low (2 days)  
**Risk:** Low

#### 9. Thermal-Aware Threading

**Problem:** Sustained decode triggers thermal throttling

**Solution:** Dynamic thread count based on temperature
```c
void adjust_thread_count(VVCContext *s) {
    float temp = get_thermal_temp();
    if (temp > 75.0f) {
        s->nb_threads = max(2, s->nb_threads - 1);
    }
}
```

**Effort:** Medium (3 days)  
**Risk:** Low

---

## Implementation Roadmap

### Phase 1: Quick Wins (Week 1-2)
1. Batch task submission
2. big.LITTLE affinity (Android)
3. Optimized buffer clearing (ARM)

**Expected Gain:** Pi5: +8%, Android: +13%, x86: +5%

### Phase 2: SIMD Optimization (Week 3-5)
4. AVX2 deblocking filter (10-bit)
5. NEON luma deblocking (10-bit)
6. ALF cache optimization (tile-based)

**Expected Gain:** Pi5: +25%, Android: +30%, x86: +15%

### Phase 3: Architecture (Week 6-8)
7. Zero-copy pipeline
8. Work-stealing task queues
9. Thermal-aware threading (Android)

**Expected Gain:** Pi5: +20%, Android: +15%, x86: +10%

### Total Expected Speedup
| Platform | Current | Optimized | Speedup |
|----------|---------|-----------|---------|
| **Pi5 (4T)** | 32 fps | 55-60 fps | **1.7x** |
| **Android (4T)** | 70 fps | 110-120 fps | **1.6x** |
| **x86 (8T)** | 214 fps | 300-340 fps | **1.5x** |

---

## Validation Checklist

For each optimization:
- [ ] Decode 500+ frames of 10-bit test content
- [ ] Verify bit-exact output (PSNR = inf)
- [ ] Measure with `perf record -g`
- [ ] Compare before/after hotspot profiles
- [ ] Test with 1, 2, 4, 8, 16 threads
- [ ] Validate on both simple and complex scenes

---

## Measurement Commands

```bash
# Profile 10-bit decode with 500 frames
perf record -g -F 999 -o perf.data \
    ./ffmpeg -c:v vvc -threads 4 \
    -i city_crowd_1920x1080.mp4 \
    -frames:v 500 -f null -

# Generate report
perf report -i perf.data --stdio --no-children -g none

# Focus on synchronization
perf report -i perf.data | grep -E '(pthread|executor|lock)'
```
