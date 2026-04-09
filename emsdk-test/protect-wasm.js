#!/usr/bin/env node
"use strict";

/**
 * WASM Protection Tool
 *
 * Encrypts ffmpeg.wasm using AES-256-GCM with a key derived from the
 * glue JS file. This ties the encrypted wasm to the specific JS build,
 * making the .wasm.enc file useless without the matching loader code.
 *
 * Usage:
 *   node protect-wasm.js <wasm-dir> [--verify]
 *
 * The tool will:
 *   1. Read ffmpeg.wasm and ffmpeg.js from <wasm-dir>
 *   2. Generate a random salt and IV
 *   3. Derive an AES-256 key from SHA256(ffmpeg.js) + salt via PBKDF2
 *   4. Encrypt ffmpeg.wasm with AES-256-GCM
 *   5. Write ffmpeg.wasm.enc and remove the original ffmpeg.wasm
 *   6. Optionally verify decryption roundtrip (--verify)
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const args = process.argv.slice(2);

if (args.length === 0 || args.includes("--help")) {
  console.log(`
WASM Protection Tool - Encrypt ffmpeg.wasm for secure distribution

Usage:
  node protect-wasm.js <wasm-dir> [--verify] [--keep-original]

Options:
  --verify          Verify decryption roundtrip after encryption
  --keep-original   Keep the original .wasm file (for debugging)
  --help            Show this help

The encrypted file format:
  [4-byte salt_len][salt][12-byte IV][16-byte auth_tag][ciphertext]
`);
  process.exit(0);
}

const wasmDir = path.resolve(args[0]);
const doVerify = args.includes("--verify");
const keepOriginal = args.includes("--keep-original");

const wasmFile = path.join(wasmDir, "ffmpeg.wasm");
const glueFile = path.join(wasmDir, "ffmpeg.js");
const encFile = path.join(wasmDir, "ffmpeg.wasm.enc");

// Validate inputs
if (!fs.existsSync(wasmFile)) {
  console.error(`Error: ${wasmFile} not found`);
  process.exit(1);
}
if (!fs.existsSync(glueFile)) {
  console.error(`Error: ${glueFile} not found`);
  process.exit(1);
}

console.log("=== WASM Protection Tool ===");
console.log(`WASM file: ${wasmFile}`);
console.log(`Glue file: ${glueFile}`);
console.log("");

// Step 1: Read files
const wasmData = fs.readFileSync(wasmFile);
const glueData = fs.readFileSync(glueFile);

console.log(`WASM size: ${(wasmData.length / 1024 / 1024).toFixed(2)} MB`);
console.log(`Glue size: ${(glueData.length / 1024).toFixed(1)} KB`);

// Step 2: Generate random salt and IV
const salt = crypto.randomBytes(32);
const iv = crypto.randomBytes(12);

// Step 3: Derive key from glue JS hash + salt
const glueHash = crypto.createHash("sha256").update(glueData).digest();
const key = crypto.pbkdf2Sync(glueHash, salt, 1000, 32, "sha256");

console.log(`Glue hash: ${glueHash.toString("hex").substring(0, 16)}...`);
console.log(`Salt:      ${salt.toString("hex").substring(0, 16)}...`);

// Step 4: Encrypt with AES-256-GCM
console.log("\nEncrypting WASM binary...");
const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
const encrypted = Buffer.concat([cipher.update(wasmData), cipher.final()]);
const authTag = cipher.getAuthTag();

// Step 5: Write encrypted bundle
// Format: [4-byte salt_len][salt][12-byte IV][16-byte auth_tag][ciphertext]
const saltLenBuf = Buffer.alloc(4);
saltLenBuf.writeUInt32LE(salt.length);

const bundle = Buffer.concat([saltLenBuf, salt, iv, authTag, encrypted]);
fs.writeFileSync(encFile, bundle);

const overhead = bundle.length - wasmData.length;
console.log(`Encrypted size: ${(bundle.length / 1024 / 1024).toFixed(2)} MB (overhead: ${overhead} bytes)`);
console.log(`Output: ${encFile}`);

// Step 6: Verify roundtrip
if (doVerify) {
  console.log("\nVerifying decryption roundtrip...");

  const readBundle = fs.readFileSync(encFile);
  let offset = 0;

  const readSaltLen = readBundle.readUInt32LE(offset);
  offset += 4;
  const readSalt = readBundle.subarray(offset, offset + readSaltLen);
  offset += readSaltLen;
  const readIv = readBundle.subarray(offset, offset + 12);
  offset += 12;
  const readAuthTag = readBundle.subarray(offset, offset + 16);
  offset += 16;
  const readCiphertext = readBundle.subarray(offset);

  const readKey = crypto.pbkdf2Sync(glueHash, readSalt, 1000, 32, "sha256");
  const decipher = crypto.createDecipheriv("aes-256-gcm", readKey, readIv);
  decipher.setAuthTag(readAuthTag);
  const decrypted = Buffer.concat([decipher.update(readCiphertext), decipher.final()]);

  if (Buffer.compare(wasmData, decrypted) === 0) {
    console.log("✓ Verification passed: decrypted data matches original");
  } else {
    console.error("✗ Verification FAILED: decrypted data does not match!");
    process.exit(1);
  }
}

// Step 7: Remove original wasm
if (!keepOriginal) {
  fs.unlinkSync(wasmFile);
  console.log(`\nRemoved original: ${wasmFile}`);
} else {
  console.log(`\nKept original: ${wasmFile}`);
}

console.log("\n=== Protection Complete ===");
console.log("The encrypted .wasm.enc file can only be loaded by the matching");
console.log("node-decode.js + ffmpeg.js combination from this build.");
