import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';

const pluginRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(pluginRoot, '..');
const checksRoot = path.join(repoRoot, 'checks', 'kubernetes');
const pluginSourcePath = path.join(pluginRoot, 'src', 'index.tsx');

const yamlFiles = (await readdir(checksRoot))
  .filter(file => file.endsWith('.yaml') && file !== 'prometheus.yaml')
  .sort();

const source = await readFile(pluginSourcePath, 'utf8');

function collectObjectKeys(objectName) {
  const startToken = `${objectName}`;
  const start = source.indexOf(startToken);
  if (start === -1) {
    return new Set();
  }

  const bodyStart = source.indexOf('{', start);
  if (bodyStart === -1) {
    return new Set();
  }

  let depth = 0;
  let end = bodyStart;
  for (; end < source.length; end += 1) {
    const char = source[end];
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        break;
      }
    }
  }

  const body = source.slice(bodyStart + 1, end);
  const keys = new Set();
  for (const match of body.matchAll(/^\s*([A-Z][A-Z0-9_]+)\s*:/gm)) {
    keys.add(match[1]);
  }
  return keys;
}

const implementedHandlers = new Set([
  ...collectObjectKeys('function podSecurityHandlers'),
  ...collectObjectKeys('const nativeHandlers'),
]);

const missingHandlers = [];

for (const file of yamlFiles) {
  const raw = await readFile(path.join(checksRoot, file), 'utf8');
  const parsed = YAML.parse(raw);
  for (const check of parsed?.checks || []) {
    if (!check.native_handler) {
      continue;
    }
    if (!implementedHandlers.has(check.native_handler)) {
      missingHandlers.push({
        checkId: check.id,
        nativeHandler: check.native_handler,
        sourceFile: file,
      });
    }
  }
}

if (missingHandlers.length > 0) {
  console.error('Missing Headlamp native handler implementations:');
  for (const item of missingHandlers) {
    console.error(`- ${item.checkId} in ${item.sourceFile} references ${item.nativeHandler}`);
  }
  console.error('');
  console.error('Add matching entries to nativeHandlers in src/index.tsx, or remove native_handler from YAML if the check can run with generated expression logic.');
  process.exit(1);
}

console.log(`Validated ${implementedHandlers.size} Headlamp native handler names.`);
