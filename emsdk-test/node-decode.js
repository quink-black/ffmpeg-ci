"use strict";

/**
 * FFmpeg HEVC WASM Decoder - Node.js CLI
 *
 * Usage:
 *   node node-decode.js <input> [options]
 *
 * Options:
 *   --frames <n>       Max frames to decode (0 = all, default: 0)
 *   --threads <n>      Number of threads (default: 1)
 *   --verify <mode>    Verification mode: none, framemd5, md5 (default: none)
 *   --warmup <n>       Warmup frames before measurement (default: 0)
 *   --help             Show this help
 */

const nodeFs = require("fs");
const nodePath = require("path");
const nodeCrypto = require("crypto");

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------
const args = process.argv.slice(2);

function showHelp() {
  console.log(`
FFmpeg HEVC WASM Decoder - Node.js CLI

Usage:
  node node-decode.js <input> [options]

Options:
  --frames <n>       Max frames to decode (0 = all, default: 0)
  --threads <n>      Number of threads (default: 1)
  --verify <mode>    Verification mode: none, framemd5, md5 (default: none)
  --warmup <n>       Warmup decode frames before measurement (default: 0)
  --help             Show this help

Examples:
  node node-decode.js input.hevc --frames 100
  node node-decode.js input.mp4 --verify framemd5 --frames 50
  node node-decode.js input.hevc --threads 4 --warmup 20 --frames 200
`);
  process.exit(0);
}

if (args.length === 0 || args.includes("--help")) {
  showHelp();
}

let inputFile = null;
let maxFrames = 0;
let threads = "1";
let verifyMode = "none";
let warmupFrames = 0;

for (let i = 0; i < args.length; i++) {
  switch (args[i]) {
    case "--frames":
      maxFrames = parseInt(args[++i]) || 0;
      break;
    case "--threads":
      threads = args[++i] || "1";
      break;
    case "--verify":
      verifyMode = args[++i] || "none";
      break;
    case "--warmup":
      warmupFrames = parseInt(args[++i]) || 0;
      break;
    default:
      if (args[i].startsWith("--")) {
        console.error(`Unknown option: ${args[i]}`);
        process.exit(1);
      }
      inputFile = args[i];
      break;
  }
}

if (!inputFile) {
  console.error("Error: No input file specified.");
  showHelp();
}

if (!["none", "framemd5", "md5"].includes(verifyMode)) {
  console.error(`Error: Invalid verify mode '${verifyMode}'. Use: none, framemd5, md5`);
  process.exit(1);
}

const resolvedInput = nodePath.resolve(inputFile);
if (!nodeFs.existsSync(resolvedInput)) {
  console.error(`Error: File not found: ${resolvedInput}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// WASM protection: decrypt the protected wasm bundle at runtime
// ---------------------------------------------------------------------------
const WASM_DIR = nodePath.resolve(__dirname, "wasm");
const PROTECTED_WASM = nodePath.join(WASM_DIR, "ffmpeg.wasm.enc");
const PLAIN_WASM = nodePath.join(WASM_DIR, "ffmpeg.wasm");
const GLUE_JS = nodePath.join(WASM_DIR, "ffmpeg.js");

/**
 * Derive decryption key from a combination of:
 *   - The glue JS file hash (ties wasm to this specific build)
 *   - A hardcoded salt embedded at package time
 * This makes the .wasm.enc file useless without the matching JS loader.
 */
function deriveKey(salt) {
  const glueHash = nodeCrypto
    .createHash("sha256")
    .update(nodeFs.readFileSync(GLUE_JS))
    .digest();
  return nodeCrypto.pbkdf2Sync(glueHash, salt, 1000, 32, "sha256");
}

function loadWasmBinary() {
  // Try protected (encrypted) wasm first
  if (nodeFs.existsSync(PROTECTED_WASM)) {
    const bundle = nodeFs.readFileSync(PROTECTED_WASM);
    // Format: [4-byte salt_len][salt][12-byte IV][16-byte auth_tag][ciphertext]
    let offset = 0;
    const saltLen = bundle.readUInt32LE(offset);
    offset += 4;
    const salt = bundle.subarray(offset, offset + saltLen);
    offset += saltLen;
    const iv = bundle.subarray(offset, offset + 12);
    offset += 12;
    const authTag = bundle.subarray(offset, offset + 16);
    offset += 16;
    const ciphertext = bundle.subarray(offset);

    const key = deriveKey(salt);
    const decipher = nodeCrypto.createDecipheriv("aes-256-gcm", key, iv);
    decipher.setAuthTag(authTag);
    const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    return new Uint8Array(decrypted);
  }

  // Fallback to plain wasm (development mode)
  if (nodeFs.existsSync(PLAIN_WASM)) {
    console.warn("[WARN] Using unprotected ffmpeg.wasm (development mode)");
    return new Uint8Array(nodeFs.readFileSync(PLAIN_WASM));
  }

  console.error("Error: No ffmpeg.wasm or ffmpeg.wasm.enc found in wasm/ directory");
  process.exit(1);
}

// ---------------------------------------------------------------------------
// FFmpeg module setup and execution
// ---------------------------------------------------------------------------
function formatBytes(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

async function main() {
  const inputBuf = nodeFs.readFileSync(resolvedInput);
  const fileName = nodePath.basename(resolvedInput);

  console.log("=== FFmpeg HEVC WASM Decoder (Node.js) ===");
  console.log(`Input:   ${resolvedInput}`);
  console.log(`Size:    ${formatBytes(inputBuf.length)}`);
  console.log(`Frames:  ${maxFrames || "all"}`);
  console.log(`Threads: ${threads}`);
  console.log(`Verify:  ${verifyMode}`);
  if (warmupFrames > 0) console.log(`Warmup:  ${warmupFrames} frames`);
  console.log("");

  // Load and decrypt WASM binary
  console.log("Loading WASM binary...");
  const wasmBinary = loadWasmBinary();
  console.log(`WASM binary loaded: ${formatBytes(wasmBinary.length)}`);

  // Track decoded frames and output
  let decodedFrames = 0;
  let framemd5Lines = [];

  // Setup Module (globalThis.Module is picked up by the patched glue JS)
  globalThis.Module = {
    noInitialRun: true,
    wasmBinary: wasmBinary.buffer,
    stdin: () => null,
    locateFile: (p) => nodePath.join(WASM_DIR, p),
    print: (text) => {
      // Capture framemd5/md5 output
      if (verifyMode === "framemd5" || verifyMode === "md5") {
        // framemd5 lines typically contain comma-separated fields or MD5= prefix
        if (text.includes("MD5=") || text.match(/^\d+,\s/)) {
          framemd5Lines.push(text);
        }
      }
      const m = text.match(/frame=\s*(\d+)/);
      if (m) decodedFrames = parseInt(m[1]);
    },
    printErr: (text) => {
      const m = text.match(/frame=\s*(\d+)/);
      if (m) decodedFrames = parseInt(m[1]);
      // Show progress on stderr
      if (text.includes("frame=") || text.includes("speed=")) {
        process.stderr.write(`\r${text.trim()}`);
      }
    },
  };

  // Load the glue JS
  console.log("Loading FFmpeg module...");
  const moduleLoadStart = Date.now();

  const runtimeReady = new Promise((resolve) => {
    globalThis.Module.onRuntimeInitialized = resolve;
  });

  require(GLUE_JS);
  await runtimeReady;

  const moduleLoadTime = Date.now() - moduleLoadStart;
  console.log(`Module loaded in ${moduleLoadTime}ms`);

  const M = globalThis.Module;

  // Write input file to virtual FS
  const vfsPath = `/input/${fileName}`;
  M.FS.mkdirTree("/input");
  M.FS.writeFile(vfsPath, new Uint8Array(inputBuf));

  // ---------------------------------------------------------------------------
  // Warmup pass (optional)
  // ---------------------------------------------------------------------------
  if (warmupFrames > 0) {
    console.log(`\nWarmup: decoding ${warmupFrames} frames...`);
    const warmupArgs = [
      "-nostdin", "-threads", threads,
      "-i", vfsPath,
      "-frames:v", String(warmupFrames),
      "-f", "null", "-"
    ];
    M.callMain(warmupArgs);
    console.log("Warmup complete.");
    decodedFrames = 0;
    framemd5Lines = [];
  }

  // ---------------------------------------------------------------------------
  // Main decode pass
  // ---------------------------------------------------------------------------
  const decodeArgs = ["-nostdin", "-threads", threads, "-i", vfsPath];
  if (maxFrames > 0) decodeArgs.push("-frames:v", String(maxFrames));

  if (verifyMode === "framemd5") {
    decodeArgs.push("-f", "framemd5", "-");
  } else if (verifyMode === "md5") {
    decodeArgs.push("-f", "md5", "-");
  } else {
    decodeArgs.push("-f", "null", "-");
  }

  console.log(`\nDecoding: ffmpeg ${decodeArgs.join(" ")}`);
  console.log("---");

  const t0 = Date.now();
  M.callMain(decodeArgs);
  const elapsed = Date.now() - t0;

  // Clear progress line
  process.stderr.write("\n");

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------
  console.log("");
  console.log("=== Results ===");
  console.log(`Decode time: ${elapsed}ms`);
  console.log(`Frames:      ${decodedFrames}`);
  if (elapsed > 0 && decodedFrames > 0) {
    console.log(`FPS:         ${(decodedFrames * 1000 / elapsed).toFixed(1)}`);
  }

  if (verifyMode !== "none" && framemd5Lines.length > 0) {
    console.log("");
    console.log(`=== ${verifyMode} output ===`);
    framemd5Lines.forEach((line) => console.log(line));
  }

  // Cleanup
  try { M.FS.unlink(vfsPath); } catch (e) { /* ignore */ }
  process.exit(0);
}

main().catch((err) => {
  console.error(`Fatal error: ${err.message}`);
  console.error(err.stack);
  process.exit(1);
});
