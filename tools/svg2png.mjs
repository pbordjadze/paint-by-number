// Rasterizes SVG files to PNG with resvg (high-quality, anti-aliased).
//   node tools/svg2png.mjs in.svg out.png [width]
import { Resvg } from '@resvg/resvg-js';
import { readFileSync, writeFileSync } from 'node:fs';
const [, , input, output, width] = process.argv;
const opts = { background: 'white', font: { loadSystemFonts: true, defaultFontFamily: 'DejaVu Sans' } };
if (width) opts.fitTo = { mode: 'width', value: Number(width) };
const png = new Resvg(readFileSync(input, 'utf8'), opts).render().asPng();
writeFileSync(output, png);
