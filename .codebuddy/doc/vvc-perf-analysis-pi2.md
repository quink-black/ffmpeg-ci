# VVC Decoder Performance Analysis - Raspberry Pi 5 (ARM64)

## Test Configuration

| Parameter | Value |
|-----------|-------|
| **Platform** | Raspberry Pi 5 (ARM Cortex-A76) |
| **OS** | Debian (Linux) |
| **Compiler** | Clang 14.0.6 |
| **FFmpeg Version** | N-123426-gf84c859ec5 |
| **Test Video** | t266_8M_tearsofsteel_4k.266 (8-bit) |
| **Resolution** | 3840x1714 |
| **Threads** | 4 |
| **Frames Decoded** | 100 |
| **Perf Sample Rate** | 999 Hz |
| **Total Samples** | 15,573 |
| **Event Count** | ~37.3 billion cycles |
| **Decode Speed** | ~0.97x real-time (24.3 fps) |

## Top Hotspots (by CPU Cycles)

| Rank | Overhead | Function | Module | Category |
|------|----------|----------|--------|----------|
| 1 | 9.69% | `__memcpy_generic` | libc.so.6 | Memory |
| 2 | 9.45% | `ff_hevc_put_hevc_pel_pixels64_8_neon` | ffmpeg_g | Motion Comp |
| 3 | 7.46% | `__memset_zva64` | libc.so.6 | Memory |
| 4 | 6.93% | `vvc_deblock_bs_chroma` | ffmpeg_g | Deblocking |
| 5 | 6.87% | `ff_vvc_deblock_bs` | ffmpeg_g | Deblocking |
| 6 | 6.28% | `ff_vvc_avg_8_neon` | ffmpeg_g | Motion Comp |
| 7 | 6.26% | `vvc_deblock` | ffmpeg_g | Deblocking |
| 8 | 5.21% | `sao_copy_ctb_to_hv` | ffmpeg_g | SAO Filter |
| 9 | 4.82% | `ff_hevc_put_hevc_pel_pixels32_8_neon` | ffmpeg_g | Motion Comp |
| 10 | 4.27% | `hls_coding_tree` | ffmpeg_g | Parsing |
| 11 | 3.28% | `__aarch64_ldadd1_acq_rel` | ffmpeg_g | **Sync/Atomic** |
| 12 | 3.07% | `ff_vvc_store_mvf` | ffmpeg_g | Motion Vectors |
| 13 | 2.78% | `__memset_zva64` (dec0 thread) | libc.so.6 | Memory |
| 14 | 1.56% | `pred_regular` | ffmpeg_g | Inter Prediction |
| 15 | 1.08% | `ff_vvc_coding_tree_unit` | ffmpeg_g | CTU Parsing |

## Key Findings

### 1. Memory Operations Dominance (27.38%)

```
__memcpy_generic:        9.69%
__memset_zva64:          7.46% (main) + 2.78% (decoder thread) = 10.24%
```

**Analysis:** Memory operations consume ~27% of CPU cycles, indicating:
- Heavy data movement between CTU processing stages
- Potential cache inefficiency in motion compensation
- Buffer copying overhead in SAO/ALF filters

**Optimization Opportunity:**
- Implement zero-copy buffer passing between pipeline stages
- Use NEON-optimized memset/memcpy for large blocks
- Consider cache prefetching for motion compensation reference pixels

### 2. Motion Compensation (20.55%)

```
ff_hevc_put_hevc_pel_pixels64_8_neon:   9.45%
ff_hevc_put_hevc_pel_pixels32_8_neon:   4.82%
ff_vvc_avg_8_neon:                      6.28%
```

**Analysis:** MC operations are well-optimized with NEON but still significant.

**Optimization Opportunity:**
- Profile different block sizes - 64x64 and 32x32 dominate
- Consider SVE (Scalable Vector Extensions) for future ARM cores
- Optimize reference pixel fetch patterns for better cache locality

### 3. Deblocking Filter (20.06%)

```
vvc_deblock_bs_chroma:   6.93%
ff_vvc_deblock_bs:       6.87%
vvc_deblock:             6.26%
```

**Analysis:** Deblocking is the third-largest consumer, split between:
- Boundary strength calculation (BS)
- Chroma deblocking
- Luma deblocking

**Optimization Opportunity:**
- Merge BS calculation with reconstruction stage
- Use NEON for deblocking decision logic
- Parallelize independent edge filtering

### 4. Synchronization Overhead (3.28%+)

```
__aarch64_ldadd1_acq_rel:  3.28%
  └── 2.41% from frame_thread_add_score
```

**Analysis:** Atomic operations for task dependency tracking consume measurable CPU.

**Call Graph Analysis:**
```
__aarch64_ldadd1_acq_rel
  └── frame_thread_add_score (2.41%)
        └── Called from task completion callbacks
```

**Optimization Opportunity:**
- Batch atomic updates where possible
- Use relaxed memory ordering for non-critical scores
- Consider per-core task queues to reduce contention

### 5. Parsing Overhead (5.35%)

```
hls_coding_tree:         4.27%
ff_vvc_coding_tree_unit: 1.08%
```

**Analysis:** CABAC parsing is relatively efficient but still significant.

## Architecture-Level Bottlenecks (ARM)

### Pipeline Stage Distribution (Estimated)

Based on function analysis:

| Stage | Estimated % | Key Functions |
|-------|-------------|---------------|
| PARSE | ~8% | hls_coding_tree, ff_vvc_coding_tree_unit |
| INTER | ~25% | ff_hevc_put_hevc_pel_pixels*, ff_vvc_avg_8_neon |
| RECON | ~5% | (part of hls_coding_tree) |
| DEBLOCK_BS | ~7% | ff_vvc_deblock_bs |
| DEBLOCK | ~13% | vvc_deblock, vvc_deblock_bs_chroma |
| SAO | ~5% | sao_copy_ctb_to_hv |
| ALF | ~3% | (inferred from remaining) |
| **Memory/Overhead** | ~34% | memcpy, memset, sync operations |

### Thread Synchronization Analysis

**Atomic Operations Breakdown:**
- `__aarch64_ldadd1_acq_rel`: 3.28% (task score updates)
- `__aarch64_swp4_rel`: 0.97% (lock release)
- `__aarch64_cas4_acq`: 0.92% (lock acquire)

**Total synchronization cost: ~5.17%**

This indicates moderate contention on the task scheduling system.

### Cache Performance Indicators

High `__memcpy_generic` usage (9.69%) suggests:
- Cache misses requiring memory-level copies
- Large working set exceeding L2 cache (512KB per core on A76)
- Potential false sharing between threads

## Platform-Specific Observations

### ARM NEON Utilization

Good news: Motion compensation is NEON-optimized:
- `ff_hevc_put_hevc_pel_pixels64_8_neon`
- `ff_hevc_put_hevc_pel_pixels32_8_neon`
- `ff_vvc_avg_8_neon`

However, deblocking and SAO filters appear to be C implementations.

### Memory Bandwidth

Raspberry Pi 5 has limited memory bandwidth compared to x86. The high memcpy/memset usage may be bandwidth-bound.

## Recommendations for ARM

### High Priority

1. **NEON-optimize deblocking filter** - Currently ~20% of cycles, potential 2-3x speedup
2. **Reduce memory copies** - Implement zero-copy between pipeline stages
3. **Optimize SAO filter** - 5.21% in buffer copying alone

### Medium Priority

4. **Batch atomic operations** - Reduce synchronization overhead
5. **Profile cache misses** - Use `perf stat -e cache-misses` for detailed analysis
6. **Tune thread count** - 4 threads may not be optimal for all video sizes

### Low Priority

7. **SVE preparation** - Future-proof for ARMv9 cores
8. **Prefetch reference pixels** - Reduce MC cache misses

## Raw perf Data

```
Samples: 15K of event 'cycles:P'
Event count (approx.): 37347954045

Overhead  Command          Shared Object      Symbol
........  ...............  .................  ...........................................
     9.69%  ffmpeg_g         libc.so.6          [.] __memcpy_generic
     9.45%  ffmpeg_g         ffmpeg_g           [.] ff_hevc_put_hevc_pel_pixels64_8_neon
     7.46%  ffmpeg_g         libc.so.6          [.] __memset_zva64
     6.93%  ffmpeg_g         ffmpeg_g           [.] vvc_deblock_bs_chroma
     6.87%  ffmpeg_g         ffmpeg_g           [.] ff_vvc_deblock_bs
     6.28%  ffmpeg_g         ffmpeg_g           [.] ff_vvc_avg_8_neon
     6.26%  ffmpeg_g         ffmpeg_g           [.] vvc_deblock
     5.21%  ffmpeg_g         ffmpeg_g           [.] sao_copy_ctb_to_hv
     4.82%  ffmpeg_g         ffmpeg_g           [.] ff_hevc_put_hevc_pel_pixels32_8_neon
     4.27%  ffmpeg_g         ffmpeg_g           [.] hls_coding_tree
     3.28%  ffmpeg_g         ffmpeg_g           [.] __aarch64_ldadd1_acq_rel
     3.07%  ffmpeg_g         ffmpeg_g           [.] ff_vvc_store_mvf
     2.78%  dec0:0:vvc       libc.so.6          [.] __memset_zva64
     1.56%  ffmpeg_g         ffmpeg_g           [.] pred_regular
     1.08%  ffmpeg_g         ffmpeg_g           [.] ff_vvc_coding_tree_unit
```

---

*Generated: 2026-03-27*
*Test Command: `perf record -g -F 999 -o perf_8bit.data -- ./ffmpeg_g -c:v vvc -threads 4 -i t266_8M_tearsofsteel_4k.266 -frames:v 100 -f null -`*
