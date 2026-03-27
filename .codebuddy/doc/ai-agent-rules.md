# AI Agent Rules for Performance Optimization Projects

> Apply to all performance analysis, acceleration evaluation, and hardware offload work.

---

## Rule 0: Never Fabricate Data

- Every performance number (%, ms, speedup) **must** cite: tool, config (preset/threads/video/frames), and machine.
- If no data exists, answer "needs measurement" — never estimate.

---

## Rule 1: Measure First — Back-of-the-Envelope Before Code

Before writing any optimization code, **must** complete and present to user:

1. `perf record` (cycles) → target function's CPU share → **T_save**
2. Estimate minimum overhead (transfer, sync, API calls) → **T_cost**
3. **Net gain = T_save − T_cost**. If < 5%, report "not viable" and recommend abort.

**Never** skip this step.

---

## Rule 2: Instruction Count ≠ Wall-Clock Time

- `callgrind` counts instructions, not cycles. For SIMD-heavy code, the gap can be **2–3×**.
- **Only use `perf record` (cycles) for speedup estimation.** callgrind is for locating hotspots only.

---

## Rule 3: Go/No-Go Is a Hard Gate

- Unmet Go/No-Go → default is **No-Go**.
- To override: must provide quantified upper-bound gain & lower-bound cost, and get user confirmation.
- **Never** bypass a quantitative rejection with qualitative reasoning ("should work in theory").

---

## Rule 4: On Failure, Challenge Assumptions First

When an approach fails:

- **Wrong**: immediately propose a "fix" for the surface symptom.
- **Right**: re-examine the fundamental assumption (is the target big enough? is overhead acceptable?). If assumption is invalid → report "direction not viable". Only if assumption holds → analyze root cause and propose fix.

**Never** chain multiple attempts without validating the underlying assumption.

---

## Rule 5: "Interesting" ≠ "Valuable"

- Before heavy implementation, answer: **does it yield quantifiable engineering benefit?**
- If uncertain, do a minimal prototype or envelope calculation first.

---

## Rule 6: Eliminate Before Exhausting

Multiple candidate directions:

- **Wrong**: implement and test all of them sequentially.
- **Right**: envelope-calc to eliminate → minimal prototype on survivors → full implementation only on validated winners.

---

## Rule 7: Cut Losses Early

**Must** proactively report and recommend stopping when any of these occur:

1. Envelope calculation shows negative net gain.
2. Two consecutive approaches yield negative measured gain.
3. Core assumption disproven by measurement.
4. Architectural blocker found (e.g., GPU results not consumed by CPU).

**Never** silently pivot to a new direction.

---

## Rule 8: Commit Before Switching

- **Must** `git commit` every working milestone.
- **Must** commit before any destructive change or direction switch.

---

## Rule 9: Validate Architecture Before Coding — Data Flow Verification

Before writing any optimization code, **must** verify the architectural feasibility:

### Data Source Verification
- Where does the target data come from?
- Is the data directly accessible (pointer/reference) or behind abstraction layers?
- What is the data format at the access point?

### Timing Verification
- When is the data generated vs. when is it consumed?
- Is the data available at the point of optimization?
- Are there any sync/async dependencies?

### Data Flow Mapping
- **Draw the data flow diagram**: Source → [Transform A] → [Buffer B] → [Transform C] → Destination
- Identify all intermediate buffers and their purposes
- Understand why temporary buffers exist — they exist for a reason

**Example from VVC SAO failure:**
- Wrong assumption: "Boundary data is in frame->data, can reference directly"
- Reality: SAO operates on temp buffer `lc->sao.buffer`; frame->data contains unfiltered reconstruction values
- Had this been verified first (gdb print / code walkthrough), the wrong direction would have been caught immediately

**Never start coding without completing this verification.**

---

## Rule 10: Stop Signs — When to Halt and Reassess

**Must stop and report immediately when:**

1. **Data source mismatch**: Assumed location ≠ actual location
2. **Timing mismatch**: Data not available when needed
3. **Hidden intermediate layer discovered**: Temp buffers, conversion layers that cannot be bypassed
4. **Debugging time exceeds 2× estimate**: If fixing takes much longer than expected, the assumption is likely wrong
5. **Architecture change required**: If optimization requires changing the architecture (not just the implementation)

**When any stop sign appears:**
- Do not attempt workarounds
- Do not chain multiple "fixes"
- Report: "Direction not viable due to [specific architectural constraint]"
- Go back to Rule 4 (challenge the fundamental assumption)
