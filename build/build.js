const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'mac');
const list = [
  'Package.swift',
  'Sources/BedrockLauncher/App.swift',
  'Sources/BedrockLauncher/GameImporter.swift',
  'Sources/BedrockLauncher/MSAuth.swift',
  'Sources/BedrockLauncher/ELFInspector.swift',
];
let tags = '';
for (const f of list) {
  const t = fs.readFileSync(path.join(root, f), 'utf8');
  if (/<\/script/i.test(t)) throw new Error('bad ' + f);
  tags += `<script type="text/plain" data-path="${f}">\n${t}</script>\n`;
}
const out = fs.readFileSync(path.join(__dirname, 'template.html'), 'utf8').replace('<!--FILES-->', () => tags);
fs.writeFileSync(path.join(__dirname, 'bedrock-launcher.html'), out);
console.log(out.length);
