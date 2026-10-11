// Batch rasterization in one node process. Jobs are {input, output, width?} objects in JSON.
// No implicit paper: isolated shapes retain alpha. External images resolve beside the SVG.
import { Resvg } from '@resvg/resvg-js';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, extname, resolve } from 'node:path';
import { Worker, isMainThread, workerData } from 'node:worker_threads';

const [, , file] = process.argv;
if (isMainThread && !file) throw new Error('usage: node tools/factory/rasterize.mjs jobs.json');
const jobs = workerData ?? JSON.parse(readFileSync(file, 'utf8'));
if (isMainThread) {
  // One node process, at most four raster threads, with no shared mutable renderer.
  const count = Math.min(4, jobs.length);
  await Promise.all(Array.from({ length: count }, (_, index) => new Promise((resolve, reject) => {
    const worker = new Worker(new URL(import.meta.url), {
      workerData: jobs.filter((_, jobIndex) => jobIndex % count === index),
    });
    worker.on('error', reject);
    worker.on('exit', code => code === 0 ? resolve() : reject(new Error(`Raster worker exited ${code}`)));
  })));
} else {
  const images = new Map();
  for (const job of jobs) {
    // resvg resolves file references from its process directory, rather than the SVG's.
    // Embed cached bytes only in this rasterization copy; the committed frame keeps its link.
    const svg = readFileSync(job.input, 'utf8').replace(/<image\b[^>]*>/g, element =>
      element.replace(/\b((?:xlink:)?href)=(['"])(.*?)\2/g, (attribute, name, quote, encoded) => {
        const href = encoded.replace(/&(amp|quot|apos|lt|gt);/g, (_, entity) =>
          ({ amp: '&', quot: '"', apos: "'", lt: '<', gt: '>' })[entity]);
        if (href.startsWith('data:')) return attribute;
        const path = resolve(dirname(job.input), href);
        if (!images.has(path)) {
          const mime = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
            '.webp': 'image/webp', '.gif': 'image/gif', '.svg': 'image/svg+xml' }[extname(path).toLowerCase()];
          if (!mime) throw new Error(`Unsupported background image: ${path}`);
          images.set(path, `data:${mime};base64,${readFileSync(path).toString('base64')}`);
        }
        return `${name}=${quote}${images.get(path)}${quote}`;
      }));
    const renderer = new Resvg(svg, {
      font: { loadSystemFonts: /<text\b/.test(svg), defaultFontFamily: 'Bitstream Charter' },
      ...(job.width ? { fitTo: { mode: 'width', value: job.width } } : {}),
    });
    writeFileSync(job.output, renderer.render().asPng());
  }
}
