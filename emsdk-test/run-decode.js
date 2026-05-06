"use strict";

// Node.js wrapper for running FFmpeg decode via emscripten VFS.

const nodeFs = require("fs");
const path = require("path");

const input = process.argv[2];
const frames = parseInt(process.argv[3]) || 100;
const threads = process.argv[4] || "1";

if (!input) {
  console.error("Usage: node run-decode.js <input.hevc> [frames] [threads]");
  process.exit(1);
}

const resolvedInput = path.resolve(input);
if (!nodeFs.existsSync(resolvedInput)) {
  console.error("File not found:", resolvedInput);
  process.exit(1);
}

// FFMPEG_WASM_DIR lets the caller select which build to benchmark (for
// side-by-side comparison of target vs. baseline). Default keeps the old
// behavior so existing scripts keep working.
const wasmDir = process.env.FFMPEG_WASM_DIR
  ? path.resolve(process.env.FFMPEG_WASM_DIR)
  : path.resolve(__dirname, "../build/ffmpeg-wasm");

global.Module = {
  noInitialRun: true,
  stdin: () => null,
  locateFile: (p) => path.join(wasmDir, p),
};

const M = require(path.join(wasmDir, "ffmpeg_g"));

M.onRuntimeInitialized = () => {
  // With NODERAWFS the wasm module sees the host filesystem directly, so
  // FFmpeg can open resolvedInput without any VFS staging.
  const args = ["-nostdin", "-threads", threads, "-i", resolvedInput];
  if (frames > 0) args.push("-frames:v", String(frames));
  args.push("-f", "null", "-");

  const t0 = Date.now();
  M.callMain(args);
  const elapsed = Date.now() - t0;

  console.log("");
  console.log("--- Results ---");
  console.log("Decode time: " + elapsed + "ms");
  if (elapsed > 0 && frames > 0) {
    console.log("FPS: " + (frames * 1000 / elapsed).toFixed(1));
  }
  process.exit(0);
};
