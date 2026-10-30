// Writes a short Y4M video of a printed table QR code, for Chromium's fake
// camera (--use-file-for-fake-video-capture). Usage:
//   node e2e/make-qr-video.mjs <text to encode> <out.y4m>
import { writeFileSync } from 'node:fs';
import QRCode from 'qrcode';

const [text, out] = process.argv.slice(2);
if (!text || !out) {
  console.error('usage: node e2e/make-qr-video.mjs <text> <out.y4m>');
  process.exit(2);
}

const width = 640;
const height = 480;
const qr = QRCode.create(text, { errorCorrectionLevel: 'M' });
const count = qr.modules.size;
const quiet = 4;
const scale = Math.floor(Math.min(width, height) * 0.8 / (count + quiet * 2));
const size = (count + quiet * 2) * scale;
const left = Math.floor((width - size) / 2);
const top = Math.floor((height - size) / 2);

// A warm grey "table" with a white card carrying the code.
const luma = Buffer.alloc(width * height, 90);
for (let y = 0; y < size; y++) {
  for (let x = 0; x < size; x++) {
    const mx = Math.floor(x / scale) - quiet;
    const my = Math.floor(y / scale) - quiet;
    const dark = mx >= 0 && my >= 0 && mx < count && my < count && qr.modules.data[my * count + mx];
    luma[(top + y) * width + left + x] = dark ? 16 : 235;
  }
}
const chroma = Buffer.alloc((width / 2) * (height / 2), 128);

const frames = 30;
const header = Buffer.from(`YUV4MPEG2 W${width} H${height} F15:1 Ip A1:1 C420jpeg\n`);
const frame = Buffer.concat([Buffer.from('FRAME\n'), luma, chroma, chroma]);
writeFileSync(out, Buffer.concat([header, ...Array.from({ length: frames }, () => frame)]));
console.log(`wrote ${out}: ${count}x${count} modules, ${frames} frames`);
