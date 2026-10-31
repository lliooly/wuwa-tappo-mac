// Recover the distinct installer/uninstaller frontend code so embedded artwork
// can be compared with the main application's Vite bundle.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const recovered = path.join(root, 'recovered/wuwa-tappo-cn-1.0.3');
const baseline = JSON.parse(fs.readFileSync(path.join(recovered, 'manifest.json'), 'utf8'));
const baselineNames = new Set(baseline.resources.map(item => item.path));
const pattern = /\/(?:assets\/[A-Za-z0-9_.-]+\.(?:js|css)|index\.html)/g;
const builds = [
  ['installer', 'WuwaTappo-cn_1.0.2_x64-setup.exe'],
  ['uninstaller', 'WuwaTappo/uninstall.exe'],
];

for (const [build, filename] of builds) {
  const input = fs.readFileSync(path.join(root, filename));
  // latin1 preserves a one-to-one correspondence between string and byte offsets.
  const binary = input.toString('latin1');
  const matches = [...binary.matchAll(pattern)].filter(match =>
    !baselineNames.has(match[0]) || match[0] === '/index.html');
  const records = [];
  const skipped = [];
  for (const match of matches) {
    const name = match[0];
    const start = match.index + name.length;
    let decoded;
    try {
      decoded = zlib.brotliDecompressSync(input.subarray(start), { info: true, maxOutputLength: 32 * 1024 * 1024 });
    } catch {
      // Matches can also occur in uncompressed data embedded inside a stream.
      skipped.push({ path: name, offset: '0x' + match.index.toString(16) });
      continue;
    }
    const output = path.join(recovered, 'art-assets/other-builds', build, 'frontend', name.slice(1));
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, decoded.buffer);
    records.push({
      path: name,
      compressedOffset: '0x' + start.toString(16),
      compressedSize: decoded.engine.bytesWritten,
      size: decoded.buffer.length,
      sha256: crypto.createHash('sha256').update(decoded.buffer).digest('hex'),
    });
  }
  const out = path.join(recovered, 'art-assets/other-builds', build, 'manifest.json');
  fs.writeFileSync(out, JSON.stringify({ source: filename, resourceCount: records.length, resources: records, skipped }, null, 2) + '\n');
  console.log(`${build}: recovered ${records.length} HTML, JS and CSS resources; ${skipped.length} non-stream matches`);
}
