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

const buf = nodeFs.readFileSync(resolvedInput);
const fileName = path.basename(resolvedInput);
const wasmDir = path.resolve(__dirname, "../build/ffmpeg-wasm");

global.Module = {
  noInitialRun: true,
  stdin: () => null,
  locateFile: (p) => path.join(wasmDir, p),
};

const M = require(path.join(wasmDir, "ffmpeg_g"));

M.onRuntimeInitialized = () => {
  const vfsPath = "/input/" + fileName;
  M.FS.mkdirTree("/input");
  M.FS.writeFile(vfsPath, buf);

  const args = ["-nostdin", "-threads", threads, "-i", vfsPath];
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
