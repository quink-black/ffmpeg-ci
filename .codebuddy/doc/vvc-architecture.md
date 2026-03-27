# FFmpeg VVC Decoder Architecture Analysis

## Overview

FFmpeg's VVC (Versatile Video Coding / H.266) decoder is a highly optimized, multi-threaded implementation supporting the VVC video compression standard. This document analyzes the decoder architecture with focus on threading, synchronization, and potential performance bottlenecks.

## 1. High-Level Architecture

### 1.1 Component Hierarchy

```
VVCContext (per decoder instance)
├── VVCFrameContext[] (per frame contexts)
│   ├── DPB (Decoded Picture Buffer) - up to 17 frames
│   ├── Parameter Sets (SPS, PPS, PH, SH)
│   ├── Threading (VVCFrameThread with FFExecutor)
│   └── Tables (CTU data, motion vectors, coefficients)
│
├── FFExecutor (thread pool)
│   ├── Worker threads
│   ├── Priority queues
│   └── Local contexts per thread
│
└── CodedBitstreamContext (CABAC parsing)
```

### 1.2 Key Data Structures

| Structure | Purpose | Instances |
|-----------|---------|-----------|
| `VVCContext` | Decoder instance state | 1 per codec context |
| `VVCFrameContext` | Per-frame decode state | Multiple (up to NB_FCS) |
| `VVCFrame` | Reference frame management | DPB_SIZE + 1 (max 18) |
| `VVCFrameThread` | Frame-level threading | 1 per VVCFrameContext |
| `VVCTask` | CTU-level work unit | 1 per CTU per stage |
| `VVCLocalContext` | Thread-local workspace | 1 per executor thread |

## 2. Threading Architecture

### 2.1 Two-Level Parallelism

The VVC decoder implements a sophisticated two-level threading model:

#### Level 1: Frame-Level Threading (FFExecutor)

```c
// libavcodec/executor.c
struct FFExecutor {
    FFTaskCallbacks cb;
    int thread_count;
    ThreadInfo *threads;
    AVMutex lock;           // Global executor lock
    AVCond cond;            // Worker thread wait condition
    Queue *q;               // Priority task queues
};
```

- Worker threads wait on a condition variable when no tasks available
- Task submission requires acquiring the global `e->lock`
- Multiple priority queues reduce contention for critical tasks

**Potential Synchronization Overhead:**
- Global lock contention when many threads submit tasks simultaneously
- Cache line bouncing on `e->lock` across CPU cores
- Condition variable wake-up latency for idle workers

#### Level 2: CTU-Level Pipeline (9-Stage)

```c
// libavcodec/vvc/thread.c
typedef enum VVCTaskStage {
    VVC_TASK_STAGE_INIT,        // CTU(0,0) only
    VVC_TASK_STAGE_PARSE,       // CABAC parsing
    VVC_TASK_STAGE_DEBLOCK_BS,  // Deblocking boundary strength
    VVC_TASK_STAGE_INTER,       // Inter prediction
    VVC_TASK_STAGE_RECON,       // Intra prediction + ITX
    VVC_TASK_STAGE_LMCS,        // Luma mapping chroma scaling
    VVC_TASK_STAGE_DEBLOCK_V,   // Vertical deblocking
    VVC_TASK_STAGE_DEBLOCK_H,   // Horizontal deblocking
    VVC_TASK_STAGE_SAO,         // Sample Adaptive Offset
    VVC_TASK_STAGE_ALF          // Adaptive Loop Filter
} VVCTaskStage;
```

### 2.2 CTU Task Dependency Model

Each CTU progresses through 9 stages with complex neighbor dependencies:

```
PARSE Stage Dependencies:
- Left CTU parse complete
- Top CTU parse complete (WPP mode)
- Colocation CTU MV availability (for temporal MVP)

INTER Stage Dependencies:
- Reference frame pixel availability at motion vector positions
- Can depend on up to 2 reference frames × up to 16 reference entries

RECON Stage Dependencies:
- Left CTU reconstruction complete
- Top-right CTU reconstruction complete

FILTER Stages Dependencies:
- Multiple neighbor CTUs for SAO/ALF (up to 8 neighbors)
```

### 2.3 Dependency Tracking Mechanism

```c
// Per-task atomic score tracking
typedef struct VVCTask {
    atomic_uchar score[VVC_TASK_STAGE_LAST];  // Dependency scores per stage
    atomic_uchar target_inter_score;           // Dynamic INTER dependencies
    // ...
} VVCTask;
```

**Target Scores by Stage:**

| Stage | Target Score | Dependencies |
|-------|--------------|--------------|
| PARSE | 2 + wpp | Left + Colocation + (WPP ? Top : 0) |
| DEBLOCK_BS | 2 | Left parse + Top parse |
| INTER | Dynamic | Reference frame pixel progress |
| RECON | 2 | Left recon + Top-right recon |
| LMCS | 3 | Right + Bottom + Bottom-right recon |
| DEBLOCK_V | 1 | Left deblock_v |
| DEBLOCK_H | 2 | Right deblock_v + Top deblock_h |
| SAO | 5 | 5 neighbors deblock_h complete |
| ALF | 8 | 8 neighbors SAO complete |

### 2.4 Progress Notification System

```c
// libavcodec/vvc/thread.c
static void report_frame_progress(VVCFrameContext *fc, const int ry, const VVCProgress idx)
{
    // Atomic increment per CTU completion
    if (atomic_fetch_add(&ft->rows[ry].col_progress[idx], 1) == ft->ctu_width - 1) {
        ff_mutex_lock(&ft->lock);  // Frame-level lock
        // Update row progress, potentially wake waiting tasks
        ff_mutex_unlock(&ft->lock);
        ff_vvc_report_progress(fc->ref, idx, progress);  // Notify other frames
    }
}
```

**Synchronization Overhead Points:**
1. **Atomic operations** on `col_progress[]` - cache coherence traffic
2. **Frame-level lock** (`ft->lock`) during row progress updates
3. **Cross-frame progress notifications** via `ff_vvc_report_progress()`

### 2.5 Progress Listener Pattern

For INTER stage, tasks register listeners on reference frames:

```c
typedef struct ProgressListener {
    VVCProgressListener l;
    VVCTask *task;
    VVCContext *s;
} ProgressListener;

// Each INTER task can have up to 2×16 = 32 listeners
VVCTask {
    ProgressListener listener[2][VVC_MAX_REF_ENTRIES];  // [L0/L1][ref_idx]
    ProgressListener col_listener;                       // Colocation
};
```

**Overhead Analysis:**
- Each listener requires atomic counter increment (`nb_scheduled_listeners`)
- Listener callback (`pixel_done`/`mv_done`) triggers task score update
- Potential thundering herd when reference frame completes row

## 3. Task Scheduling Analysis

### 3.1 Priority-Based Scheduling

```c
// libavcodec/vvc/thread.c
static const int priorities[] = {
    0,                  // INIT (highest)
    0,                  // PARSE
    1,                  // DEBLOCK_BS
    PRIORITY_LOWEST,    // INTER - deprioritized to avoid overwhelming
    1,                  // RECON
    1,                  // LMCS
    1,                  // DEBLOCK_V
    1,                  // DEBLOCK_H
    1,                  // SAO
    1,                  // ALF
};
```

**Rationale for INTER Priority:**
> "For an 8K clip, a CTU line completed in the reference frame may trigger 64 and more inter tasks. We assign these tasks the lowest priority to avoid being overwhelmed with inter tasks."

### 3.2 Task Granularity and Scheduling Overhead

| Stage | Typical Work | Scheduling Frequency | Overhead Risk |
|-------|-------------|---------------------|---------------|
| PARSE | CABAC decode (variable) | 1× per CTU | Medium |
| INTER | Motion compensation | 1× per CTU | High (lowest priority) |
| RECON | Intra + ITX | 1× per CTU | Medium |
| DEBLOCK_V/H | Edge filtering | 1× per CTU | Medium |
| SAO | Sample offset | 1× per CTU | Low |
| ALF | Adaptive filtering | 1× per CTU | Low |

**For 4K video (68×38 CTUs):**
- Total tasks per frame: 68×38×9 = 23,256 task instances
- Task submission requires: atomic increment + potential queue insertion

### 3.3 Lock Contention Pattern

```c
// Task submission path (hot path)
static void add_task(VVCContext *s, VVCTask *t)
{
    atomic_fetch_add(&ft->nb_scheduled_tasks, 1);  // Atomic
    task->priority = priorities[t->stage];
    ff_executor_execute(s->executor, task);        // Acquires e->lock
}

// ff_executor_execute - in executor.c
void ff_executor_execute(FFExecutor *e, FFTask *t)
{
    ff_mutex_lock(&e->lock);   // Global lock
    add_task(e->q + t->priority, t);
    ff_cond_signal(&e->cond);  // Wake a worker
    ff_mutex_unlock(&e->lock);
}
```

**Contention Scenarios:**
1. **Burst task submissions** when dependency chain unlocks many CTUs
2. **Frame boundary** when new frame tasks compete with completing frame
3. **High thread counts** (e.g., 16+ threads) on small frames

## 4. Memory Access Patterns

### 4.1 Thread-Local Context

```c
// libavcodec/vvc/ctu.h
typedef struct VVCLocalContext {
    union {
        struct {
            DECLARE_ALIGNED(32, uint8_t, edge_emu_buffer)[EDGE_EMU_BUFFER_STRIDE * EDGE_EMU_BUFFER_STRIDE * 2];
            DECLARE_ALIGNED(32, int16_t, tmp)[MAX_PB_SIZE * MAX_PB_SIZE];
            // ... 32KB+ per thread
        } pred;
        struct {
            DECLARE_ALIGNED(32, uint8_t, buffer)[(MAX_CTU_SIZE + 2 * SAO_PADDING_SIZE) * EDGE_EMU_BUFFER_STRIDE * 2];
        } sao;
        struct {
            DECLARE_ALIGNED(32, uint8_t, buffer_luma)[(MAX_CTU_SIZE + 2 * ALF_PADDING_SIZE) * EDGE_EMU_BUFFER_STRIDE * 2];
            DECLARE_ALIGNED(32, int32_t, gradient_tmp)[ALF_GRADIENT_SIZE * ALF_GRADIENT_SIZE * ALF_NUM_DIR];
            // ... 48KB+ per thread
        } alf;
    };
} VVCLocalContext;
```

**Memory Footprint:** ~80-120KB per thread for local contexts

### 4.2 Frame Data Access Patterns

| Data Structure | Access Pattern | Cache Impact |
|---------------|----------------|--------------|
| `tab.cus[]` | Per-CTU sequential | Good locality |
| `tab.mvf[]` | Random (motion vectors) | Poor locality |
| `tab.coeffs[]` | Per-TU sequential | Good locality |
| Reference frames | Random (motion comp) | Poor locality, cache misses |

### 4.3 False Sharing Risks

```c
// Potential false sharing locations:
VVCFrameThread {
    atomic_int nb_scheduled_tasks;      // Shared across all threads
    atomic_int nb_scheduled_listeners;  // Shared across all threads
    VVCRowThread *rows;                 // Per-row atomic counters
};

VVCRowThread {
    atomic_int col_progress[VVC_PROGRESS_LAST];  // Cache line per row
};
```

## 5. Potential Bottleneck Analysis

### 5.1 Architecture-Level Bottlenecks

| Bottleneck | Impact | Evidence |
|------------|--------|----------|
| **Pipeline dependency chains** | Limits parallelism | RECON→LMCS→DEBLOCK→SAO→ALF sequential per CTU |
| **WPP entropy coding** | Parse serialization | `sps_entropy_coding_sync_enabled_flag` forces row-wise parse |
| **INTER dependency explosion** | Thread starvation | Single CTU can wait for 64+ reference regions |
| **Global executor lock** | Contention at scale | All task submissions serialize on `e->lock` |
| **Frame-level progress lock** | Contention | `ft->lock` during row progress updates |

### 5.2 Function-Level Hotspots (Expected)

Based on code analysis, expect these hotspots:

| Function | File | Reason |
|----------|------|--------|
| `ff_vvc_predict_inter()` | inter.c | Motion compensation, MC interpolation |
| `ff_vvc_reconstruct()` | intra.c | Intra prediction + inverse transform |
| `ff_vvc_coding_tree_unit()` | ctu.c | CABAC parsing, variable complexity |
| `ff_vvc_deblock_*()` | filter.c | Edge filtering on all CTU boundaries |
| `ff_vvc_sao_filter()` | filter.c | Sample offset application |
| `ff_vvc_alf_filter()` | filter.c | Complex adaptive filtering |
| `ff_vvc_executor_execute()` | executor.c | Task scheduling overhead |
| `run_one_task()` | executor.c | Task dispatch overhead |

### 5.3 Synchronization Overhead Hotspots

```c
// High-frequency atomic operations:
atomic_fetch_add(&t->score[stage], 1)           // Per dependency resolution
atomic_fetch_add(&ft->nb_scheduled_tasks, 1)    // Per task submit
atomic_fetch_add(&ft->rows[ry].col_progress[idx], 1)  // Per CTU stage complete
atomic_load(&t->score[stage])                   // Per ready check

// Lock acquisitions:
ff_mutex_lock(&e->lock)                         // Per task submit
ff_mutex_lock(&ft->lock)                        // Per row progress update
```

## 6. Profiling Strategy

### 6.1 perf Events to Monitor

```bash
# CPU cycles and hotspots
perf record -g -- ./ffmpeg -c:v vvc -i test.vvc -f null -

# Cache performance
perf stat -e cycles,instructions,cache-misses,cache-references \
    ./ffmpeg -c:v vvc -i test.vvc -f null -

# Scheduler statistics
perf stat -e context-switches,cpu-migrations,page-faults \
    ./ffmpeg -c:v vvc -i test.vvc -f null -

# Synchronization overhead (if available)
perf stat -e raw_syscalls:sys_enter,futexes \
    ./ffmpeg -c:v vvc -i test.vvc -f null -
```

### 6.2 Key Metrics to Extract

1. **Top-down analysis** (cycles distribution)
2. **Function-level hotspots** (CPU % per function)
3. **Cache miss rates** (data vs instruction)
4. **Lock contention** (time in mutex operations)
5. **Thread efficiency** (parallelism achieved vs potential)

### 6.3 Platform-Specific Considerations

**Raspberry Pi 5 (ARM Cortex-A76):**
- Smaller L1/L2 caches (64KB/512KB per core)
- Lower memory bandwidth than x86
- NEON SIMD for DSP functions

**x86 (black2):**
- Larger caches, higher bandwidth
- AVX2/AVX-512 potential for DSP
- Different branch prediction behavior

## 7. Optimization Opportunities (Pre-Analysis)

### 7.1 Scheduling Optimizations

1. **Batch task submission** - Reduce executor lock acquisitions
2. **Work-stealing queues** - Reduce global contention
3. **Affinity-aware scheduling** - Keep CTU processing on same core

### 7.2 Synchronization Optimizations

1. **Reduce atomic operations** - Batch score updates
2. **Lock-free progress tracking** - Use seqlocks or RCU pattern
3. **Reduce INTER dependencies** - Predictive scheduling

### 7.3 Algorithm Optimizations

1. **SIMD acceleration** - NEON (ARM) / AVX2 (x86) for hot DSP functions
2. **Memory prefetching** - For motion compensation
3. **Cache-friendly data layouts** - Reorganize CTU data structures

## 8. Document References

- VVC Specification: ITU-T Rec. H.266
- FFmpeg VVC decoder: `libavcodec/vvc/`
- Thread executor: `libavcodec/executor.c`
- Task system: `libavcodec/vvc/thread.c`

---

*Document generated from source code analysis. Performance numbers to be filled after perf profiling.*
