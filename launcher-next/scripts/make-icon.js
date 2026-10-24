const sharp = require('sharp');
const pngToIco = require('png-to-ico');
const fs = require('fs');
const path = require('path');

(async () => {
  const root = path.resolve(__dirname, '..');
  const source = path.join(root, 'assets', 'azpc-account-logo.png');
  const { data, info } = await sharp(source)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  // Extract the diamond only, without the AZPC wordmark or solid backdrop.
  const side = Math.min(info.height, 78);
  const left = 4;
  const top = Math.max(0, Math.floor((info.height - side) / 2));
  const pixels = Buffer.alloc(side * side * 4);
  for (let y = 0; y < side; y++) {
    for (let x = 0; x < side; x++) {
      const src = ((y + top) * info.width + (x + left)) * info.channels;
      const dst = (y * side + x) * 4;
      const r = data[src], g = data[src + 1], b = data[src + 2];
      // The original artwork has a near-black rectangular background.
      // Use brightness as alpha so the diamond itself remains visible.
      const luminance = Math.max(r, g, b);
      const alpha = Math.round(255 * Math.min(1, Math.max(0, (luminance - 16) / 90)));
      pixels[dst] = r;
      pixels[dst + 1] = g;
      pixels[dst + 2] = b;
      pixels[dst + 3] = alpha;
    }
  }
  const diamond = await sharp(pixels, { raw: { width: side, height: side, channels: 4 } })
    .trim({ background: '#00000000', threshold: 12 })
    .resize(236, 236, { fit: 'contain', kernel: 'lanczos3' })
    .extend({ top: 10, bottom: 10, left: 10, right: 10, background: '#00000000' })
    .png()
    .toBuffer();
  fs.writeFileSync(path.join(root, 'assets', 'azpc-icon.png'), diamond);
  fs.writeFileSync(path.join(root, 'assets', 'azpc.ico'), await pngToIco(diamond));
  console.log('Created transparent AZPC diamond icon, 256x256');
})().catch(error => { console.error(error); process.exit(1); });
