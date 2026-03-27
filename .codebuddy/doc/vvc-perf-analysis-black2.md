# VVC Decoder Performance Analysis - x86 (black2)

## Test Configuration

| Parameter | Value |
|-----------|-------|
| **Platform** | x86_64 Linux Workstation |
| **OS** | Ubuntu 24.04 |
| **Compiler** | GCC 14.2.0 |
| **FFmpeg Version** | N-123625-g719c9e1fe1 |
| **Test Video** | t266_8M_tearsofsteel_4k.266 (8-bit) |
| **Resolution** | 3840x1714 |
| **Threads** | 8 |
| **Frames Decoded** | 100 |
| **Perf Sample Rate** | 999 Hz |
| **Total Samples** | 8,213 |
| **Event Count** | ~34.5 billion cycles |
| **Decode Speed** | ~3.92x real-time (99 fps) |

## Top Hotspots (by CPU Cycles)

| Rank | Overhead | Function | Module | Category |
|------|----------|----------|--------|----------|
| 1 | 8.38% | `ff_h2656_put_pixels32_8_avx2` | ffmpeg_g | Motion Comp |
| 2 | 6.80% | `__memset_avx2_unaligned_erms` | libc.so.6 | Memory |
| 3 | 5.74% | `hls_coding_tree` | ffmpeg_g | Parsing |
| 4 | 5.05% | `__memmove_avx_unaligned_erms` | libc.so.6 | Memory |
| 5 | 4.16% | `ff_vvc_set_mvf` | ffmpeg_g | Motion Vectors |
| 6 | 4.05% | `vvc_deblock_bs_chroma` | ffmpeg_g | Deblocking |
| 7 | 3.72% | `ff_vvc_deblock_bs` | ffmpeg_g | Deblocking |
| 8 | 3.26% | `frame_thread_add_score` | ffmpeg_g | **Scheduling** |
| 9 | 2.85% | `sao_copy_ctb_to_hv` | ffmpeg_g | SAO Filter |
| 10 | 2.65% | `ff_vvc_avg_8_avx2` | ffmpeg_g | Motion Comp |
| 11 | 2.44% | `__memset_avx2_unaligned_erms` (dec0) | libc.so.6 | Memory |
| 12 | 2.33% | `ff_vvc_deblock_vertical` | ffmpeg_g | Deblocking |
| 13 | 2.02% | `ff_vvc_deblock_horizontal` | ffmpeg_g | Deblocking |
| 14 | 1.72% | `pthread_mutex_lock` | libc.so.6 | **Sync** |
| 15 | 1.63% | `pred_regular` | ffmpeg_g | Inter Prediction |
| 16 | 1.36% | `pthread_mutex_unlock` | libc.so.6 | **Sync** |
| 17 | 1.06% | `ff_vvc_report_progress` | ffmpeg_g | **Sync** |
| 18 | 1.04% | `executor_worker_task` | ffmpeg_g | **Scheduling** |
| 19 | 1.04% | `ff_vvc_frame_thread_init` (dec0) | ffmpeg_g | Init |

## Key Findings

### 1. Motion Compensation with AVX2 (11.03%)

```
ff_h2656_put_pixels32_8_avx2:   8.38%
ff_vvc_avg_8_avx2:              2.65%
```

**Analysis:** AVX2-optimized MC is performing well, but 32-pixel width dominates (not 64-pixel).

**Call Graph:**
```
ff_h2656_put_pixels32_8_avx2
  ├── 5.43% from main execution path
  └── 2.94% from secondary path
```

**Optimization Opportunity:**
- Add AVX2 64-pixel wide kernels for large blocks
- Profile block size distribution to optimize kernel selection

### 2. Memory Operations (14.29%)

```
__memset_avx2_unaligned_erms:   6.80% (main) + 2.44% (decoder) = 9.24%
__memmove_avx_unaligned_erms:   5.05%
```

**Analysis:** Memory operations consume ~14% of cycles, less than ARM's 27%.

**Reasons for better performance:**
- x86 has higher memory bandwidth
- AVX2-optimized memset/memmove in glibc
- Better cache hierarchy (larger L2/L3)

### 3. Critical: Scheduling & Synchronization (8.44%)

```
frame_thread_add_score:         3.26%  ← Task scheduling
pthread_mutex_lock:             1.72%  ← Lock contention
pthread_mutex_unlock:           1.36%  ← Lock release
ff_vvc_report_progress:         1.06%  ← Progress notification
executor_worker_task:           1.04%  ← Worker thread overhead
```

**Total scheduling/sync overhead: ~8.44%**

**Analysis:** This is a significant finding - nearly 8.5% of CPU cycles are spent on task scheduling and synchronization, higher than ARM's ~5%.

**Call Graph for frame_thread_add_score:**
```
frame_thread_add_score
  ├── 1.46% from direct calls
  └── 0.87% from callback paths
```

**Root Cause:**
- Higher thread count (8 vs 4) increases contention
- Global executor lock (`e->lock`) becomes bottleneck
- More frequent task submissions from more threads

### 4. Deblocking Filter (11.10%)

```
vvc_deblock_bs_chroma:          4.05%
ff_vvc_deblock_bs:              3.72%
ff_vvc_deblock_vertical:        2.33%
ff_vvc_deblock_horizontal:      2.02%
```

**Analysis:** Deblocking is well-distributed across stages but still significant.

**Optimization Opportunity:**
- AVX2 optimization for deblocking filters
- Merge BS calculation with parsing stage

### 5. Motion Vector Management (4.16%)

```
ff_vvc_set_mvf:                 4.16%
```

**Analysis:** Setting motion vector fields is surprisingly high on x86.

**Call Graph:**
```
ff_vvc_set_mvf
  ├── 4.10% direct execution
```

**Optimization Opportunity:**
- Batch MVF updates
- Use SIMD for MV field initialization

### 6. SAO Filter (2.85%)

```
sao_copy_ctb_to_hv:             2.85%
```

**Analysis:** Lower than ARM (5.21%), likely due to better memory bandwidth.

## Architecture-Level Bottlenecks (x86)

### Pipeline Stage Distribution (Estimated)

| Stage | Estimated % | Key Functions |
|-------|-------------|---------------|
| PARSE | ~10% | hls_coding_tree |
| INTER | ~15% | ff_h2656_put_pixels32_8_avx2, ff_vvc_avg_8_avx2 |
| RECON | ~3% | (part of hls_coding_tree) |
| DEBLOCK_BS | ~8% | ff_vvc_deblock_bs, vvc_deblock_bs_chroma |
| DEBLOCK | ~8% | ff_vvc_deblock_vertical/horizontal |
| SAO | ~3% | sao_copy_ctb_to_hv |
| ALF | ~2% | (inferred) |
| **Scheduling/Sync** | ~8% | frame_thread_add_score, mutex ops |
| **Memory** | ~14% | memset, memmove |
| **Other** | ~29% | ff_vvc_set_mvf, pred_regular, etc. |

### Thread Synchronization Analysis

**Mutex Operations:**
- `pthread_mutex_lock`: 1.72%
- `pthread_mutex_unlock`: 1.36%
- `ff_vvc_report_progress`: 1.06%

**Task Scheduling:**
- `frame_thread_add_score`: 3.26%
- `executor_worker_task`: 1.04%

**Total synchronization cost: ~8.44%**

**Comparison with ARM:**
| Platform | Sync Overhead | Thread Count |
|----------|---------------|--------------|
| ARM (Pi5) | ~5.17% | 4 |
| x86 (black2) | ~8.44% | 8 |

**Insight:** Synchronization overhead scales with thread count. The global executor lock becomes a bottleneck at 8 threads.

### Cache Performance

Lower memory operation overhead (~14% vs ~27% on ARM) indicates:
- Better cache hit rates
- Higher memory bandwidth
- More efficient prefetching

## Platform-Specific Observations

### AVX2 Utilization

Good AVX2 coverage in:
- Motion compensation: `ff_h2656_put_pixels32_8_avx2`
- Averaging: `ff_vvc_avg_8_avx2`
- Memory: `__memset_avx2_unaligned_erms`

Missing AVX2 optimizations:
- Deblocking filter (C code)
- SAO filter (C code)
- Motion vector field management

### Thread Scaling

With 8 threads achieving 3.92x speedup (99 fps), the decoder shows good but not perfect scaling.

**Amdahl's Law Analysis:**
- 8.44% synchronization overhead limits theoretical max speedup
- Additional threads beyond 8 may show diminishing returns

## Cross-Platform Comparison

| Metric | ARM (Pi5) | x86 (black2) | Ratio |
|--------|-----------|--------------|-------|
| **Decode Speed** | 0.97x | 3.92x | 4.0x |
| **Memory Overhead** | ~27% | ~14% | 0.5x |
| **Sync Overhead** | ~5% | ~8% | 1.6x |
| **MC Performance** | NEON | AVX2 | Similar |
| **Thread Count** | 4 | 8 | 2x |

**Key Insights:**
1. x86 is 4x faster overall due to better memory subsystem
2. ARM spends 2x more time on memory operations
3. x86 has higher sync overhead due to more threads
4. Both platforms would benefit from SIMD-optimized deblocking

## Recommendations for x86

### High Priority

1. **Reduce scheduling overhead** - The 8.44% is too high
   - Implement work-stealing queues per thread
   - Batch task submissions
   - Use lock-free structures where possible

2. **AVX2-optimize deblocking filter** - Currently ~11% in C code
   - Potential 2-3x speedup
   - Similar to what NEON provides on ARM

3. **Optimize ff_vvc_set_mvf** - 4.16% is unexpectedly high
   - Use AVX2 for bulk MV field operations
   - Batch updates to reduce cache thrashing

### Medium Priority

4. **Add AVX-512 kernels** - For future processors
5. **Profile L3 cache misses** - Use `perf stat -e cache-misses`
6. **Tune thread count** - 8 may be too many for some resolutions

### Low Priority

7. **SAO filter AVX2** - Lower impact (~3%)
8. **Optimize pred_regular** - 1.63% with potential for SIMD

## Critical Finding: Scheduling Bottleneck

The most important finding for x86 is the **8.44% scheduling/synchronization overhead**. This indicates:

1. **Global lock contention** on `FFExecutor.lock`
2. **Frequent task submissions** triggering lock acquisitions
3. **Progress notification overhead** with many threads

### Recommended Solutions

1. **Per-thread task queues** with work-stealing
2. **Batch task submission** - Submit multiple tasks per lock acquisition
3. **Reduce dependency checks** - Pre-compute dependency graphs
4. **Adaptive thread count** - Reduce threads for smaller videos

## Raw perf Data

```
Samples: 8K of event 'cycles:P'
Event count (approx.): 34517674281

Overhead  Command          Shared Object         Symbol
........  ...............  ....................  ................................................
     8.38%  ffmpeg_g         ffmpeg_g              [.] ff_h2656_put_pixels32_8_avx2
     6.80%  ffmpeg_g         libc.so.6             [.] __memset_avx2_unaligned_erms
     5.74%  ffmpeg_g         ffmpeg_g              [.] hls_coding_tree
     5.05%  ffmpeg_g         libc.so.6             [.] __memmove_avx_unaligned_erms
     4.16%  ffmpeg_g         ffmpeg_g              [.] ff_vvc_set_mvf
     4.05%  ffmpeg_g         ffmpeg_g              [.] vvc_deblock_bs_chroma
     3.72%  ffmpeg_g         ffmpeg_g              [.] ff_vvc_deblock_bs
     3.26%  ffmpeg_g         ffmpeg_g              [.] frame_thread_add_score
     2.85%  ffmpeg_g         ffmpeg_g              [.] sao_copy_ctb_to_hv
     2.65%  ffmpeg_g         ffmpeg_g              [.] ff_vvc_avg_8_avx2
     2.44%  dec0:0:vvc       libc.so.6             [.] __memset_avx2_unaligned_erms
     2.33%  ffmpeg_g         ffmpeg_g              [.] ff_vvc_deblock_vertical
     2.02%  ffmpeg_g         ffmpeg_g              [.] ff_vvc_deblock_horizontal
     1.72%  ffmpeg_g         libc.so.6             [.] pthread_mutex_lock
     1.63%  ffmpeg_g         ffmpeg_g              [.] pred_regular
     1.36%  ffmpeg_g         libc.so.6             [.] pthread_mutex_unlock
     1.06%  ffmpeg_g         ffmpeg_g              [.] ff_vvc_report_progress
     1.04%  ffmpeg_g         ffmpeg_g              [.] executor_worker_task
     1.04%  dec0:0:vvc       ffmpeg_g              [.] ff_vvc_frame_thread_init
```

---

*Generated: 2026-03-27*
*Test Command: `perf record -g -F 999 -o perf_8bit.data -- ./ffmpeg_g -c:v vvc -threads 8 -i t266_8M_tearsofsteel_4k.266 -frames:v 100 -f null -`*
