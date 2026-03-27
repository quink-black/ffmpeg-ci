# VVC Decoder Optimization Guide

## Executive Summary

This guide presents optimization recommendations for FFmpeg's VVC decoder based on performance analysis on ARM (Raspberry Pi 5) and x86 (black2) platforms.

### Key Findings

| Category | ARM (Pi5) | x86 (black2) | Priority |
|----------|-----------|--------------|----------|
| **Memory Operations** | 27.4% | 14.3% | **Critical** |
| **Scheduling/Sync** | 5.2% | 8.4% | **High** |
| **Deblocking Filter** | 20.1% | 11.1% | **High** |
| **Motion Compensation** | 20.6% | 11.0% | Medium |
| **SAO Filter** | 5.2% | 2.9% | Medium |

### Critical Bottleneck Identified

**Task Scheduling Overhead scales with thread count:**
- 4 threads (ARM): ~5% overhead
- 8 threads (x86): ~8.4% overhead

This indicates the global executor lock becomes a bottleneck at higher thread counts.

---

## 1. Architecture-Level Optimizations

### 1.1 Task Scheduling System Redesign

**Current Problem:**
```c
// Global lock for all task operations
ff_mutex_lock(&e->lock);   // Contention point
task_submit();
ff_mutex_unlock(&e->lock);
```

**Recommended Solution: Work-Stealing Queues**

```c
// Per-thread task queue
struct ThreadQueue {
    FFTask *head;
    FFTask *tail;
    AVMutex lock;  // Only for stealing
};

struct FFExecutor {
    ThreadQueue *queues;  // One per thread
    // Global lock only for shutdown
};
```

**Expected Impact:**
- Reduce scheduling overhead from 8.4% to ~3%
- Better scalability beyond 8 threads
- Lower cache coherence traffic

**Implementation Complexity:** High
**Estimated Speedup:** 5-10% on high-thread-count systems

### 1.2 Batch Task Submission

**Current Problem:** Each task completion triggers immediate scheduling:
```c
// Called for every CTU stage completion
frame_thread_add_score(s, ft, rx, ry, stage);  // One task at a time
```

**Recommended Solution:**
```c
// Batch multiple ready tasks
typedef struct TaskBatch {
    VVCTask *tasks[16];
    int count;
} TaskBatch;

// Submit batch when threshold reached or at end of processing
void submit_task_batch(VVCContext *s, TaskBatch *batch);
```

**Expected Impact:**
- Reduce lock acquisitions by 5-10x
- Lower synchronization overhead

**Implementation Complexity:** Medium
**Estimated Speedup:** 3-5%

### 1.3 Lock-Free Progress Tracking

**Current Problem:**
```c
atomic_fetch_add(&ft->rows[ry].col_progress[idx], 1);  // Per CTU
ff_mutex_lock(&ft->lock);  // Frame-level lock
// Update progress
ff_mutex_unlock(&ft->lock);
```

**Recommended Solution: Seqlock Pattern**
```c
typedef struct SeqLockProgress {
    atomic_uint sequence;  // Even = readable, Odd = writing
    int progress;
} SeqLockProgress;

// Reader (lock-free)
uint seq = atomic_load(&sp->sequence);
if (seq % 2 == 0) {
    int prog = sp->progress;
    if (atomic_load(&sp->sequence) == seq) {
        // Valid read
    }
}
```

**Expected Impact:**
- Eliminate frame-level lock contention
- Reduce atomic operations

**Implementation Complexity:** Medium
**Estimated Speedup:** 2-4%

---

## 2. Function-Level Optimizations

### 2.1 Deblocking Filter SIMD Optimization

**Current State:** C implementation consuming 11-20% of cycles

**ARM NEON Implementation:**
```c
// vvc_deblock_neon.c
void ff_vvc_deblock_vertical_neon(uint8_t *pix, ptrdiff_t stride,
                                   int beta, int tc, int count);
void ff_vvc_deblock_horizontal_neon(uint8_t *pix, ptrdiff_t stride,
                                     int beta, int tc, int count);
```

**x86 AVX2 Implementation:**
```c
// vvc_deblock_avx2.c
void ff_vvc_deblock_vertical_avx2(uint8_t *pix, ptrdiff_t stride,
                                   int beta, int tc, int count);
void ff_vvc_deblock_horizontal_avx2(uint8_t *pix, ptrdiff_t stride,
                                     int beta, int tc, int count);
```

**Expected Speedup:**
- ARM: 2-3x faster (reduce 20% → 7%)
- x86: 2-3x faster (reduce 11% → 4%)

**Implementation Complexity:** High
**Priority:** **CRITICAL**

### 2.2 Motion Vector Field Optimization

**Current Problem:** `ff_vvc_set_mvf` consumes 4.16% on x86

**Optimization Strategy:**
```c
// Batch MV field updates
void ff_vvc_set_mvf_batch(VVCFrameContext *fc, MvField *mvs, int count) {
    // Use SIMD for bulk copy
    #if HAVE_AVX2
        // 256-bit stores for MV fields
    #elif HAVE_NEON
        // 128-bit stores for MV fields
    #else
        // Fallback
    #endif
}
```

**Expected Speedup:** 2-3x for MV operations
**Implementation Complexity:** Medium
**Priority:** Medium

### 2.3 Memory Copy Elimination

**Current Problem:** memcpy/memset consumes 14-27% of cycles

**Zero-Copy Pipeline:**
```c
// Current: Copy between stages
void sao_copy_ctb_to_hv(VVCFrameContext *fc, int rx, int ry) {
    // Copies CTB data to horizontal/vertical buffers
    memcpy(h_buffer, src, size);
    memcpy(v_buffer, src, size);
}

// Optimized: Use pointer swapping
typedef struct CTUBuffers {
    uint8_t *data;      // Main buffer
    uint8_t *h_border;  // Pointer to H border within data
    uint8_t *v_border;  // Pointer to V border within data
} CTUBuffers;
```

**Expected Speedup:**
- Eliminate 50% of memcpy operations
- Reduce memory bandwidth by 10-15%

**Implementation Complexity:** High
**Priority:** **HIGH**

---

## 3. Platform-Specific Optimizations

### 3.1 ARM (Raspberry Pi 5)

#### 3.1.1 NEON Deblocking Filter

**Target Functions:**
- `vvc_deblock_bs_chroma` (6.93%)
- `ff_vvc_deblock_bs` (6.87%)
- `vvc_deblock` (6.26%)

**Implementation Approach:**
```c
// Process 8 pixels at a time with NEON
int8x16_t p0 = vld1q_s8(pix - 4);
int8x16_t p1 = vld1q_s8(pix - 3);
int8x16_t p2 = vld1q_s8(pix - 2);
int8x16_t p3 = vld1q_s8(pix - 1);
int8x16_t q0 = vld1q_s8(pix);
// ... deblocking logic
```

**Expected Impact:** Reduce deblocking from 20% to 7%

#### 3.1.2 Cache Prefetching for MC

```c
// In motion compensation
void prefetch_reference_pixels(const uint8_t *ref, int stride, int bw, int bh) {
    for (int y = 0; y < bh; y += 64) {
        __builtin_prefetch(ref + y * stride, 0, 3);
    }
}
```

**Expected Impact:** Reduce MC cache misses by 20-30%

### 3.2 x86 (black2)

#### 3.2.1 Reduce Thread Contention

**Problem:** 8.44% scheduling overhead with 8 threads

**Solution:** Adaptive Thread Count
```c
int optimal_thread_count(int width, int height) {
    int ctu_count = ((width + 63) / 64) * ((height + 63) / 64);
    // Use fewer threads for smaller videos
    if (ctu_count < 100) return 4;
    if (ctu_count < 300) return 6;
    return 8;
}
```

**Expected Impact:** Reduce sync overhead from 8.4% to ~5%

#### 3.2.2 AVX2 Deblocking Filter

Same approach as NEON, but with 256-bit registers.

**Expected Impact:** Reduce deblocking from 11% to 4%

#### 3.2.3 AVX-512 Support

For future processors, implement AVX-512 kernels:
```c
#if HAVE_AVX512
void ff_vvc_put_pixels64_8_avx512(...);
void ff_vvc_deblock_vertical_avx512(...);
#endif
```

---

## 4. Optimization Priority Matrix

| Optimization | Impact | Complexity | Priority | Platform |
|--------------|--------|------------|----------|----------|
| **NEON Deblocking** | High | High | **P0** | ARM |
| **AVX2 Deblocking** | High | High | **P0** | x86 |
| **Zero-Copy Pipeline** | High | High | **P1** | Both |
| **Work-Stealing Queues** | Medium | High | **P1** | Both |
| **Batch Task Submit** | Medium | Medium | **P2** | Both |
| **Lock-Free Progress** | Low | Medium | **P2** | Both |
| **MVF SIMD** | Medium | Medium | **P2** | Both |
| **AVX-512 Kernels** | Medium | Medium | **P3** | x86 |
| **SVE Support** | Medium | High | **P3** | ARM |

---

## 5. Implementation Roadmap

### Phase 1: Quick Wins (1-2 weeks)

1. **Batch task submission** - 3-5% speedup
2. **Adaptive thread count** - 3-5% speedup on x86
3. **Cache prefetching** - 2-3% speedup

### Phase 2: SIMD Optimizations (4-6 weeks)

1. **NEON deblocking filter** - 10-15% speedup on ARM
2. **AVX2 deblocking filter** - 5-8% speedup on x86
3. **MVF SIMD optimization** - 2-3% speedup

### Phase 3: Architecture Improvements (6-8 weeks)

1. **Zero-copy pipeline** - 10-15% speedup
2. **Work-stealing queues** - 5-10% speedup
3. **Lock-free progress tracking** - 2-4% speedup

---

## 6. Measurement & Validation

### 6.1 Benchmarking Protocol

```bash
# Baseline measurement
perf stat -r 5 -e cycles,instructions,cache-misses,cache-references \
    ./ffmpeg -c:v vvc -threads N -i test.vvc -frames:v 100 -f null -

# Key metrics to track:
# - Cycles per frame
# - Instructions per cycle (IPC)
# - Cache miss rate
# - Decode FPS
```

### 6.2 Regression Testing

Test with multiple video types:
- 8-bit vs 10-bit
- 1080p vs 4K
- Low motion vs high motion
- I-frame heavy vs P/B-frame heavy

### 6.3 Thread Scaling Analysis

Measure speedup with 1, 2, 4, 8, 16 threads to verify scalability improvements.

---

## 7. Expected Overall Speedup

### Conservative Estimates

| Platform | Current FPS | Optimized FPS | Speedup |
|----------|-------------|---------------|---------|
| ARM (Pi5) | 24.3 | 35-40 | **1.4-1.6x** |
| x86 (black2) | 99 | 120-140 | **1.2-1.4x** |

### Breakdown by Optimization

| Optimization | ARM Gain | x86 Gain |
|--------------|----------|----------|
| SIMD Deblocking | +15% | +8% |
| Zero-Copy Pipeline | +10% | +8% |
| Scheduling Improvements | +5% | +10% |
| Other SIMD | +10% | +8% |
| **Total** | **+40%** | **+34%** |

---

## 8. References

- Architecture Document: `vvc-architecture.md`
- ARM Performance Analysis: `vvc-perf-analysis-pi2.md`
- x86 Performance Analysis: `vvc-perf-analysis-black2.md`
- FFmpeg VVC Source: `/Users/quink/work/ffmpeg_all/ffmpeg/libavcodec/vvc/`

---

*Generated: 2026-03-27*
*Based on perf analysis of 100 frames of t266_8M_tearsofsteel_4k.266*
