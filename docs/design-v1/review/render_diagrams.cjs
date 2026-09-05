// 文档矢量图的只读渲染检查；每次输出到独立目录，不覆盖旧文件。
const fs = require('fs');
const path = require('path');
const sharp = require('C:/Users/admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const base = path.resolve(__dirname, '..');
const out = path.join(__dirname, 'render-' + Date.now());
fs.mkdirSync(out, { recursive: true });
(async () => {
  for (const name of fs.readdirSync(path.join(base, 'assets'))) {
    if (!name.endsWith('.svg')) continue;
    const source = path.join(base, 'assets', name);
    const target = path.join(out, name.replace(/\.svg$/, '.png'));
    await sharp(source).png().toFile(target);
    process.stdout.write(target + '\n');
  }
})().catch(error => { process.stderr.write(String(error)); process.exitCode = 1; });
