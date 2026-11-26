import { createHash } from 'node:crypto';
import {
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { transform } from 'esbuild';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const srcDir = path.join(rootDir, 'website');
const outDir = path.join(rootDir, 'websitedist');

function shortHash(content) {
  return createHash('sha256').update(content).digest('hex').slice(0, 8);
}

function minifyHtml(html) {
  return html
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/>\s+</g, '><')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

async function buildWebsite() {
  mkdirSync(outDir, { recursive: true });
  rmSync(path.join(outDir, 'assets'), { recursive: true, force: true });
  rmSync(path.join(outDir, 'index.html'), { force: true });

  const cssOutDir = path.join(outDir, 'assets', 'css');
  const jsOutDir = path.join(outDir, 'assets', 'js');
  const imgOutDir = path.join(outDir, 'assets', 'img');
  mkdirSync(cssOutDir, { recursive: true });
  mkdirSync(jsOutDir, { recursive: true });
  mkdirSync(imgOutDir, { recursive: true });

  const cssRaw = readFileSync(path.join(srcDir, 'assets', 'css', 'styles.css'), 'utf8');
  const cssResult = await transform(cssRaw, { loader: 'css', minify: true });
  const cssHash = shortHash(cssResult.code);
  const cssFileName = `styles.${cssHash}.css`;
  writeFileSync(path.join(cssOutDir, cssFileName), cssResult.code, 'utf8');

  const jsRaw = readFileSync(path.join(srcDir, 'assets', 'js', 'main.js'), 'utf8');
  const jsResult = await transform(jsRaw, {
    loader: 'js',
    minify: true,
    target: 'es2020',
  });
  const jsHash = shortHash(jsResult.code);
  const jsFileName = `main.${jsHash}.js`;
  writeFileSync(path.join(jsOutDir, jsFileName), jsResult.code, 'utf8');

  const imgSrcDir = path.join(srcDir, 'assets', 'img');
  const assetMap = new Map([
    ['assets/css/styles.css', `assets/css/${cssFileName}`],
    ['assets/js/main.js', `assets/js/${jsFileName}`],
  ]);

  for (const file of readdirSync(imgSrcDir)) {
    const raw = readFileSync(path.join(imgSrcDir, file));
    const ext = path.extname(file);
    const base = path.basename(file, ext);
    let content = raw;
    if (ext.toLowerCase() === '.svg') {
      const minifiedSvg = minifyHtml(raw.toString('utf8'));
      content = Buffer.from(minifiedSvg, 'utf8');
    }
    const hash = shortHash(content);
    const hashedName = `${base}.${hash}${ext}`;
    writeFileSync(path.join(imgOutDir, hashedName), content);
    assetMap.set(`assets/img/${file}`, `assets/img/${hashedName}`);
  }

  let html = readFileSync(path.join(srcDir, 'index.html'), 'utf8');
  for (const [from, to] of assetMap.entries()) {
    html = html.split(from).join(to);
  }
  const minifiedHtml = minifyHtml(html);
  writeFileSync(path.join(outDir, 'index.html'), `${minifiedHtml}\n`, 'utf8');

  console.log(
    `[build:website] Built websitedist/ (CSS: ${cssFileName}, JS: ${jsFileName})`
  );
}

buildWebsite().catch((err) => {
  console.error('[build:website] Failed:', err);
  process.exit(1);
});
