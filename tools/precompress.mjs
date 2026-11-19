// Writes Brotli (.br) and gzip (.gz) copies of a web build's text assets, at
// maximum compression, so the API serves them ready-made instead of
// compressing on every request (smaller, and no CPU per request).
//
//   node tools/precompress.mjs <build dir>
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { brotliCompressSync, constants, gzipSync } from 'node:zlib';

const dir = process.argv[2];
if (!dir) throw new Error('Usage: node tools/precompress.mjs <build dir>');
const compressible = /\.(js|mjs|css|svg|ttf|otf|json|webmanifest|txt|map)$/i;
let before = 0, after = 0, files = 0;

function walk(path) {
  for (const name of readdirSync(path)) {
    const full = join(path, name);
    if (statSync(full).isDirectory()) walk(full);
    else if (compressible.test(name) && statSync(full).size >= 1024) {
      const data = readFileSync(full);
      const br = brotliCompressSync(data, {
        params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_SIZE_HINT]: data.length },
      });
      writeFileSync(`${full}.br`, br);
      writeFileSync(`${full}.gz`, gzipSync(data, { level: 9 }));
      before += data.length; after += br.length; files++;
    }
  }
}
walk(dir);
console.log(`precompressed ${files} files: ${Math.round(before / 1024)} KB -> ${Math.round(after / 1024)} KB (brotli)`);
