import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const kubebuddyVersionInput = process.argv[2];
const pluginVersionArg = process.argv.find(arg => arg.startsWith('--plugin-version='));
const checksumArg = process.argv.find(arg => arg.startsWith('--checksum='));
const shouldBumpPluginPatch = process.argv.includes('--bump-plugin-patch');

if (!kubebuddyVersionInput) {
  throw new Error(
    'Usage: node scripts/prepare-headlamp-plugin-release.mjs <kubebuddy-version> [--plugin-version=<x.y.z> | --bump-plugin-patch] [--checksum=<sha256>]'
  );
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const kubebuddyVersion = kubebuddyVersionInput.startsWith('v')
  ? kubebuddyVersionInput
  : `v${kubebuddyVersionInput}`;

if (!/^v\d+\.\d+\.\d+$/.test(kubebuddyVersion)) {
  throw new Error(`KubeBuddy version must use vX.Y.Z format. Got: ${kubebuddyVersionInput}`);
}

const packageJsonPath = path.join(root, 'headlamp-plugin', 'package.json');
const packageLockPath = path.join(root, 'headlamp-plugin', 'package-lock.json');
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
const checksum = checksumArg?.replace('--checksum=', '');

if (pluginVersionArg && shouldBumpPluginPatch) {
  throw new Error('Use either --plugin-version or --bump-plugin-patch, not both.');
}

function bumpPatchVersion(version) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) {
    throw new Error(`Plugin version must use X.Y.Z format. Got: ${version}`);
  }

  const [major, minor, patch] = version.split('.').map(Number);
  return `${major}.${minor}.${patch + 1}`;
}

const pluginVersion = pluginVersionArg?.replace('--plugin-version=', '') ||
  (shouldBumpPluginPatch ? bumpPatchVersion(packageJson.version) : packageJson.version);

if (!/^\d+\.\d+\.\d+$/.test(pluginVersion)) {
  throw new Error(`Plugin version must use X.Y.Z format. Got: ${pluginVersion}`);
}

function writeJson(relativePath, data) {
  fs.writeFileSync(path.join(root, relativePath), `${JSON.stringify(data, null, 2)}\n`);
}

packageJson.version = pluginVersion;
writeJson('headlamp-plugin/package.json', packageJson);

const packageLock = JSON.parse(fs.readFileSync(packageLockPath, 'utf8'));
packageLock.version = pluginVersion;
if (packageLock.packages?.['']) {
  packageLock.packages[''].version = pluginVersion;
}
writeJson('headlamp-plugin/package-lock.json', packageLock);

const archiveUrl = `https://github.com/KubeDeckio/KubeBuddy/releases/download/${kubebuddyVersion}/kubebuddy-headlamp-plugin-${pluginVersion}.tar.gz`;
let artifactHub = fs.readFileSync(path.join(root, 'headlamp-plugin', 'artifacthub-pkg.yml'), 'utf8');

artifactHub = artifactHub
  .replace(/^version: .+$/m, `version: ${pluginVersion}`)
  .replace(/version: \d+\.\d+\.\d+/g, `version: ${pluginVersion}`)
  .replace(/includes KubeBuddy checks from v\d+\.\d+\.\d+/g, `includes KubeBuddy checks from ${kubebuddyVersion}`)
  .replace(
    /headlamp\/plugin\/archive-url: "[^"]+"/,
    `headlamp/plugin/archive-url: "${archiveUrl}"`
  )
  .replace(/kubebuddy\.io\/checks-version: "[^"]+"/, `kubebuddy.io/checks-version: "${kubebuddyVersion}"`);

if (checksum) {
  artifactHub = artifactHub.replace(
    /headlamp\/plugin\/archive-checksum: "SHA256:[^"]+"/,
    `headlamp/plugin/archive-checksum: "SHA256:${checksum}"`
  );
}

fs.writeFileSync(path.join(root, 'headlamp-plugin', 'artifacthub-pkg.yml'), artifactHub);

let readme = fs.readFileSync(path.join(root, 'headlamp-plugin', 'README.md'), 'utf8');
readme = readme
  .replace(/Plugin version: \d+\.\d+\.\d+/g, `Plugin version: ${pluginVersion}`)
  .replace(/version: \d+\.\d+\.\d+/g, `version: ${pluginVersion}`)
  .replace(/Includes KubeBuddy checks from v\d+\.\d+\.\d+/g, `Includes KubeBuddy checks from ${kubebuddyVersion}`)
  .replace(/kubebuddy-headlamp-plugin-\d+\.\d+\.\d+\.tar\.gz/g, `kubebuddy-headlamp-plugin-${pluginVersion}.tar.gz`);
fs.writeFileSync(path.join(root, 'headlamp-plugin', 'README.md'), readme);
