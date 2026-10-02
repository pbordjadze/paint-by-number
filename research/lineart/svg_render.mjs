// Rasterizes a batch of SVG files with resvg: node svg_render.mjs jobs.json
// jobs.json: [{"svg": path, "png": path, "width": px, "background": "#rrggbb" | null, "font": ttf path}]
// (run from a directory where @resvg/resvg-js is installed; layers.py copies this file there).
import { Resvg } from '@resvg/resvg-js';
import { readFileSync, writeFileSync } from 'node:fs';
const jobs = JSON.parse(readFileSync(process.argv[2], 'utf8'));
for (const job of jobs) {
  const opts = {
    fitTo: { mode: 'width', value: job.width },
    font: { loadSystemFonts: false, fontFiles: job.font ? [job.font] : [], defaultFontFamily: 'Source Serif 4' },
  };
  if (job.background) opts.background = job.background;
  const png = new Resvg(readFileSync(job.svg, 'utf8'), opts).render().asPng();
  writeFileSync(job.png, png);
}
