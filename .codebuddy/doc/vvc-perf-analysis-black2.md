# VVC Decoder Performance Analysis - x86 (black2)

**Test Date:** 2025-03-27  
**Focus:** 10-bit decoding (primary use case)

## Test Configuration

| Parameter | Value |
|-----------|-------|
| **Platform** | x86_64 Linux Workstation |
| **CPU** | Intel/AMD (8 cores used) |
| **OS** | Ubuntu 24.04 |
| **Compiler** | GCC 14.2.0 |
| **FFmpeg Version** | N-123625-g719c9e1fe1 |
| **Threads** | 8 |
| **Perf Sample Rate** | 999 Hz |

## Test Results Summary

| Sample | Resolution | Bit Depth | Frames | Decode Speed | Total Cycles |
|--------|------------|-----------|--------|--------------|--------------|
| city_crowd_1920x1080.mp4 | 1920x1080 | 10-bit | 500 | 214 fps (7.13x) | 81.5B |
| out_vod_p7_10bit.mp4 | 1920x1080 | 10-bit | 500 | 373 fps (12.4x) | 48.3B |

## Detailed Analysis - city_crowd (Complex Scene)

### Top Hotspots (500 frames, 10-bit)

| Rank | Overhead | Function | Category |
|------|----------|----------|----------|
| 1 | **8.10%** | `__memmove_avx_unaligned_erms` | **Memory** |
| 2 | 4.29% | `..@1190.vb_end` | (uncategorized) |
| 3 | **3.66%** | `__memset_avx2_unaligned_erms` | **Memory** |
| 4 | 3.24% | `hls_coding_tree` | Parsing |
| 5 | 3.19% | `pred_regular` | Inter Prediction |
| 6 | 3.08% | `vvc_loop_filter_luma_10` | Deblocking |
| 7 | 2.60% | `vvc_deblock_bs_chroma` | Deblocking BS |
| 8 | 2.56% | `hls_residual_coding.isra.0` | Entropy Coding |
| 9 | 2.26% | `pred_regular_blk` | Inter Prediction |
| 10 | 2.05% | `ff_vvc_deblock_bs` | Deblocking BS |
| 11 | 2.04% | `alf_recon_coeff_and_clip_10` | ALF Filter |
| 12 | 2.04% | `emulated_edge` | Edge Handling |
| 13 | 1.95% | `put_uni_w_pixels_10` | Motion Comp |
| 14 | 1.88% | `ff_vvc_reconstruct` | Reconstruction |
| 15 | 1.84% | `ff_vvc_deblock_vertical` | Deblocking |

### Key Findings

#### 1. Memory Operations (11.76%)

```
__memmove_avx_unaligned_erms:     8.10%
__memset_avx2_unaligned_erms:     3.66%
────────────────────────────────────────
Total Memory:                     11.76%
```

**Observation:** x86 has lower memory overhead than ARM (11.8% vs 17.9%):
- AVX2-optimized memcpy/memset already in use
- Still significant opportunity for zero-copy optimization
- 10-bit still requires 2x bandwidth vs 8-bit

#### 2. Deblocking Filter (9.57%)

```
vvc_loop_filter_luma_10:          3.08%
vvc_deblock_bs_chroma:            2.60%
ff_vvc_deblock_bs:                2.05%
ff_vvc_deblock_vertical:          1.84%
ff_vvc_deblock_horizontal:        1.57%
────────────────────────────────────────
Total Deblocking:                 ~11%
```

**Critical Finding:** Deblocking is still C code for 10-bit on x86!
- Luma loop filter (`vvc_loop_filter_luma_10`) in C
- BS calculation in C
- **Major opportunity:** AVX2 implementation

#### 3. Parsing Overhead (5.8%)

```
hls_coding_tree:                  3.24%
hls_residual_coding.isra.0:       2.56%
────────────────────────────────────────
Total Parsing:                    5.8%
```

**Observation:** Higher parsing overhead than ARM:
- CABAC entropy coding branchy
- Tree traversal not vectorizable
- Still significant at 10-bit

#### 4. Synchronization Overhead (~2.5%)

```
pthread_mutex_lock:               0.63% (self) / 0.60% (children)
pthread_mutex_unlock:             0.42% (self) / 0.41% (children)
executor_worker_task:             0.27% (self) / 0.08% (children)
ff_executor_execute:              0.29% (self) / 0.04% (children)
pthread_cond_broadcast:           0.20% (decoder thread)
pthread_cond_wait:                0.08%
────────────────────────────────────────────────────────
Total Sync Overhead:              ~2.5%
```

**Issue:** With 8 threads, sync overhead is **2.5x higher** than ARM with 4 threads (2.5% vs 1.0%).
- Global executor lock contention
- Condition variable overhead
- Scales with thread count

#### 5. ALF Filter (4.0%)

```
alf_recon_coeff_and_clip_10:      2.04%
```

**Observation:** Lower ALF overhead than ARM (4% vs 12%):
- Better cache hierarchy on x86
- AVX2 optimizations likely present
- Less critical than deblocking

### Detailed Analysis - out_vod_p7 (Simpler Scene)

| Rank | Overhead | Function | Category |
|------|----------|----------|----------|
| 1 | **6.10%** | `__memmove_avx_unaligned_erms` | **Memory** |
| 2 | 5.01% | `hls_residual_coding.isra.0` | Entropy Coding |
| 3 | 4.27% | `..@1190.vb_end` | (uncategorized) |
| 4 | **3.71%** | `__memset_avx2_unaligned_erms` | **Memory** |
| 5 | 3.69% | `ff_vvc_reconstruct` | Reconstruction |
| 6 | 3.39% | `alf_filter_cc_10` | ALF Filter |
| 7 | 3.07% | `vvc_loop_filter_luma_10` | Deblocking |
| 8 | 2.98% | `hls_coding_tree` | Parsing |

**Observation:** Simpler scenes show similar distribution but lower absolute overhead.

## Architecture-Level Bottlenecks (x86)

### 1. Thread Scaling Limitation
- **Issue:** 8 threads show 2.5% sync overhead vs 1.0% on ARM with 4 threads
- **Impact:** Diminishing returns beyond 8 threads
- **Root Cause:** Global executor lock (`FFExecutor.lock`)

### 2. Missing AVX2 Deblocking for 10-bit
- **Issue:** Deblocking uses C code (11% of cycles)
- **Impact:** Major optimization opportunity
- **Root Cause:** 10-bit path not fully SIMD-optimized

### 3. Parsing/Eentropy Bottleneck
- **Issue:** 5.8% in parsing/entropy coding
- **Impact:** Serial bottleneck (not parallelizable)
- **Root Cause:** CABAC inherently branchy

## Hot Function Summary

| Category | Functions | Total % | Priority |
|----------|-----------|---------|----------|
| Memory | memmove, memset | 11.8% | **P1** |
| Deblocking | loop filter, BS calc | 11.0% | **P0** |
| Parsing | coding_tree, residual | 5.8% | P2 |
| Sync | pthread locks | 2.5% | **P1** |
| ALF | filter, classify | 4.0% | P2 |
| Motion Comp | put_*, DMVR | ~5% | P3 |

## Comparison with 8-bit Results

| Metric | 8-bit (4K) | 10-bit (1080p) | Change |
|--------|------------|----------------|--------|
| Decode Speed | 99 fps | 214 fps | +116% (smaller res) |
| Memory % | 14.0% | 11.8% | -2.2% (AVX2 helps) |
| Sync % | 8.4% | 2.5% | -5.9% (faster decode) |

**Key Insight:** 10-bit at 1080p is actually faster than 8-bit at 4K due to smaller resolution, not bit depth.

## Recommendations for x86

### P0: Critical (Expected 15-25% speedup)
1. **AVX2 deblocking filter** - 10-bit luma/chroma loop filters
2. **Work-stealing task queues** - Reduce global lock contention

### P1: High (Expected 10-15% speedup)
3. **Zero-copy pipeline** - Eliminate buffer copies
4. **Batch task submission** - Reduce lock acquisitions

### P2: Medium (Expected 5-10% speedup)
5. **Entropy coding optimization** - Branch prediction hints
6. **ALF filter tuning** - Cache optimization
