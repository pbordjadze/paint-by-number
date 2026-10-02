// Opens lines.svg files in Chromium (Playwright) over a paper background, checks the groups
// and counts what rendered, and saves a screenshot per file:
//   NODE_PATH=/opt/node22/lib/node_modules node svg_check.cjs out_dir a.svg [b.svg ...]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [outDir, ...files] = process.argv.slice(2);
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3 });
  let failed = 0;
  for (const f of files) {
    const svg = fs.readFileSync(f, 'utf8');
    await page.setContent(`<html><body style="margin:0;background:#F4EFE6">
      <div style="width:390px">${svg.replace('<svg ', '<svg style="width:390px;height:auto;display:block" ')}</div>
      </body></html>`);
    const info = await page.evaluate(() => {
      const g = id => document.querySelector(`g#${id}`);
      const box = document.querySelector('svg').getBoundingClientRect();
      return {
        groups: ['top', 'mid', 'inner', 'color', 'numbers'].map(id => [id, g(id) ? g(id).children.length : -1]),
        width: box.width, height: box.height,
        topLength: g('top') ? [...g('top').querySelectorAll('path')].reduce((s, p) => s + p.getTotalLength(), 0) : 0,
      };
    });
    const ok = info.groups.every(([, n]) => n >= 0) && info.width > 0 && info.topLength > 0;
    if (!ok) failed++;
    const name = f.split(path.sep).slice(-3).join('_').replace('.svg', '.png');
    await page.screenshot({ path: path.join(outDir, name) });
    console.log(ok ? 'ok  ' : 'FAIL', f, JSON.stringify(info));
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
