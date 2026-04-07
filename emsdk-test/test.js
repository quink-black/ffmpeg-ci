"use strict";

const WASM_BUILD_PATH = "../build/ffmpeg-wasm";

const logEl = document.getElementById("log");
const btnDecode = document.getElementById("btnDecode");
const btnProfile = document.getElementById("btnProfile");
const btnClear = document.getElementById("btnClear");
const inputFile = document.getElementById("inputFile");
const maxFramesEl = document.getElementById("maxFrames");
const resultsEl = document.getElementById("results");

let fileData = null;
let fileName = null;

function log(msg, cls) {
  const span = document.createElement("span");
  span.className = cls || "";
  span.textContent = msg + "\n";
  logEl.appendChild(span);
  logEl.scrollTop = logEl.scrollHeight;
}

function logInfo(msg) { log(msg, "log-info"); }
function logOk(msg) { log(msg, "log-ok"); }
function logErr(msg) { log(msg, "log-err"); }
function logPerf(msg) { log(msg, "log-perf"); }

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

function updateStats(frames, timeMs, inputSize) {
  resultsEl.style.display = "grid";
  document.getElementById("statFrames").textContent = frames;
  document.getElementById("statTime").textContent = timeMs.toFixed(0);
  document.getElementById("statFPS").textContent =
    timeMs > 0 ? (frames * 1000 / timeMs).toFixed(1) : "-";
  document.getElementById("statSize").textContent = formatBytes(inputSize);
}

inputFile.addEventListener("change", (e) => {
  const file = e.target.files[0];
  if (!file) return;

  fileName = file.name;
  logInfo(`Loading file: ${fileName} (${formatBytes(file.size)})`);

  const reader = new FileReader();
  reader.onload = () => {
    fileData = new Uint8Array(reader.result);
    logOk(`File loaded: ${formatBytes(fileData.length)}`);
    btnDecode.disabled = false;
    btnProfile.disabled = false;
  };
  reader.onerror = () => logErr("Failed to read file");
  reader.readAsArrayBuffer(file);
});

btnClear.addEventListener("click", () => {
  logEl.innerHTML = "";
  resultsEl.style.display = "none";
});

async function loadFFmpegModule() {
  logInfo("Loading FFmpeg WASM module...");
  const t0 = performance.now();

  const scriptUrl = `${WASM_BUILD_PATH}/ffmpeg_g`;
  const resp = await fetch(scriptUrl);
  if (!resp.ok) {
    throw new Error(
      `Failed to load ffmpeg JS glue: ${resp.status} ${resp.statusText}\n` +
      `URL: ${scriptUrl}\n` +
      `Make sure serve.sh is running from the ffmpeg-ci directory.`
    );
  }

  let scriptText = await resp.text();

  // emscripten modules export via Module or createModule
  // We need to override Module to capture stdout/stderr
  const collectedOutput = [];
  let decodedFrames = 0;

  const moduleOverrides = {
    noInitialRun: true,
    print: (text) => {
      log(text);
      // Parse ffmpeg output for frame count
      const m = text.match(/frame=\s*(\d+)/);
      if (m) decodedFrames = parseInt(m[1]);
    },
    printErr: (text) => {
      // ffmpeg writes progress to stderr
      const m = text.match(/frame=\s*(\d+)/);
      if (m) decodedFrames = parseInt(m[1]);
      log(text);
      collectedOutput.push(text);
    },
  };

  // Create a blob URL with the module script
  const blob = new Blob(
    [`var Module = ${JSON.stringify(moduleOverrides)};\n` + scriptText],
    { type: "application/javascript" }
  );
  const blobUrl = URL.createObjectURL(blob);

  // Use dynamic import via script tag
  await new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = blobUrl;
    script.onload = resolve;
    script.onerror = reject;
    document.head.appendChild(script);
  });

  // Wait for the module to be ready
  if (typeof Module !== "undefined" && Module.onRuntimeInitialized) {
    await new Promise((resolve) => {
      const orig = Module.onRuntimeInitialized;
      Module.onRuntimeInitialized = () => {
        if (typeof orig === "function") orig();
        resolve();
      };
    });
  } else if (typeof Module !== "undefined") {
    // Wait for calledRun or just a small delay for initialization
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  const loadTime = performance.now() - t0;
  logOk(`Module loaded in ${loadTime.toFixed(0)}ms`);

  return { Module: window.Module, collectedOutput, getFrames: () => decodedFrames };
}

async function runDecode(doProfile) {
  if (!fileData) {
    logErr("No file loaded");
    return;
  }

  const maxFrames = parseInt(maxFramesEl.value) || 0;
  btnDecode.disabled = true;
  btnProfile.disabled = true;

  try {
    logInfo("--- Starting decode ---");
    logInfo(`File: ${fileName}, Max frames: ${maxFrames || "all"}`);

    if (doProfile) {
      logInfo("Starting Chrome DevTools profile...");
      logInfo("Open DevTools (F12) > Performance tab > Record to capture profile");
      console.profile("FFmpeg HEVC Decode");
    }

    const { Module: mod, getFrames } = await loadFFmpegModule();

    // Write input file to emscripten virtual filesystem
    const vfsPath = `/tmp/${fileName}`;
    logInfo(`Writing ${formatBytes(fileData.length)} to virtual FS: ${vfsPath}`);
    mod.FS.writeFile(vfsPath, fileData);

    // Build ffmpeg arguments
    const args = ["-i", vfsPath];
    if (maxFrames > 0) {
      args.push("-frames:v", String(maxFrames));
    }
    args.push("-f", "null", "-");

    logInfo(`Running: ffmpeg ${args.join(" ")}`);

    const t0 = performance.now();
    mod.callMain(args);
    const elapsed = performance.now() - t0;

    if (doProfile) {
      console.profileEnd("FFmpeg HEVC Decode");
      logInfo("Profile captured. Check DevTools > Performance tab.");
    }

    const frames = getFrames();
    logPerf(`\n=== Results ===`);
    logPerf(`Decode time: ${elapsed.toFixed(0)}ms`);
    logPerf(`Frames: ${frames}`);
    if (elapsed > 0 && frames > 0) {
      logPerf(`FPS: ${(frames * 1000 / elapsed).toFixed(1)}`);
    }

    updateStats(frames, elapsed, fileData.length);

    // Cleanup virtual FS
    try { mod.FS.unlink(vfsPath); } catch (e) { /* ignore */ }

  } catch (err) {
    logErr(`Error: ${err.message}`);
    logErr(err.stack || "");
  } finally {
    btnDecode.disabled = false;
    btnProfile.disabled = false;
  }
}

btnDecode.addEventListener("click", () => runDecode(false));
btnProfile.addEventListener("click", () => runDecode(true));

// Check cross-origin isolation
if (!crossOriginIsolated) {
  logErr("WARNING: Cross-Origin Isolation is NOT enabled.");
  logErr("SharedArrayBuffer (required for pthreads) may not work.");
  logErr("Use serve.sh to start the server with correct headers.");
} else {
  logOk("Cross-Origin Isolation: enabled (SharedArrayBuffer available)");
}

logInfo("Ready. Select an HEVC stream file to begin.");
