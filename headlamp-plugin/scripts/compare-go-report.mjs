import { readFile } from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_IGNORED_PREFIXES = ['PROM', 'AKS', 'GKE'];
const DEFAULT_IGNORED_IDS = ['SC002'];

function usage() {
  console.error(`Usage:
  npm run compare:go -- <go-json-report> <headlamp-json-report> [options]

Options:
  --ignore-prefix=CSV  Check ID prefixes to ignore. Default: ${DEFAULT_IGNORED_PREFIXES.join(',')}
  --ignore-id=CSV      Exact check IDs to ignore. Default: ${DEFAULT_IGNORED_IDS.join(',')}
  --strict-findings    Also fail when finding counts differ for checks with matching status.
  --show-matches       Print matching check IDs.

Examples:
  npm run compare:go -- ../reports/kubebuddy-report.json ../reports/kubebuddy-cluster.json
  npm run compare:go -- ../reports/go.json ../reports/plugin.json --ignore-prefix=PROM,AKS,GKE --strict-findings`);
}

function parseArgs(argv) {
  const files = [];
  const options = {
    ignoredPrefixes: [...DEFAULT_IGNORED_PREFIXES],
    ignoredIds: [...DEFAULT_IGNORED_IDS],
    strictFindings: false,
    showMatches: false,
  };

  for (const arg of argv) {
    if (arg === '--help' || arg === '-h') {
      usage();
      process.exit(0);
    }
    if (arg === '--strict-findings') {
      options.strictFindings = true;
      continue;
    }
    if (arg === '--show-matches') {
      options.showMatches = true;
      continue;
    }
    if (arg.startsWith('--ignore-prefix=')) {
      options.ignoredPrefixes = csv(arg.slice('--ignore-prefix='.length));
      continue;
    }
    if (arg.startsWith('--ignore-id=')) {
      options.ignoredIds = csv(arg.slice('--ignore-id='.length));
      continue;
    }
    if (arg.startsWith('--')) {
      throw new Error(`Unknown option ${arg}`);
    }
    files.push(arg);
  }

  if (files.length !== 2) {
    usage();
    process.exit(2);
  }

  return { goPath: files[0], pluginPath: files[1], options };
}

function csv(value) {
  return value
    .split(',')
    .map(item => item.trim().toUpperCase())
    .filter(Boolean);
}

async function readJson(filePath) {
  const raw = await readFile(filePath, 'utf8');
  return JSON.parse(raw);
}

function checksFromReport(report, label) {
  if (Array.isArray(report?.checks)) {
    return report.checks;
  }
  if (report?.checks && typeof report.checks === 'object') {
    return Object.values(report.checks);
  }
  if (Array.isArray(report?.Checks)) {
    return report.Checks;
  }
  throw new Error(`${label} does not look like a KubeBuddy JSON report: expected checks/Checks`);
}

function normalizeReport(report, label) {
  const checks = new Map();

  for (const check of checksFromReport(report, label)) {
    const id = String(check?.id || check?.ID || '').trim().toUpperCase();
    if (!id) {
      continue;
    }

    checks.set(id, {
      id,
      name: String(check?.name || check?.Name || ''),
      status: normalizeStatus(check),
      findingCount: normalizeFindingCount(check),
      findings: normalizeFindings(check),
    });
  }

  return checks;
}

function normalizeStatus(check) {
  const explicit = String(check?.status || check?.Status || '').toLowerCase();
  if (explicit.includes('skip')) {
    return 'skipped';
  }
  if (explicit.includes('fail')) {
    return 'failed';
  }
  if (explicit.includes('pass')) {
    return 'passed';
  }

  const total = Number(check?.Total ?? check?.total);
  if (Number.isFinite(total)) {
    return total > 0 ? 'failed' : 'passed';
  }

  const findings = check?.findings || check?.Items || check?.items;
  return Array.isArray(findings) && findings.length > 0 ? 'failed' : 'passed';
}

function normalizeFindingCount(check) {
  const total = Number(check?.Total ?? check?.total);
  if (Number.isFinite(total)) {
    return total;
  }

  const findings = check?.findings || check?.Items || check?.items;
  if (Array.isArray(findings)) {
    return findings.length;
  }

  return normalizeStatus(check) === 'failed' ? 1 : 0;
}

function normalizeFindings(check) {
  const findings = check?.findings || check?.Items || check?.items;
  if (!Array.isArray(findings)) {
    return [];
  }

  return findings.map(finding => ({
    namespace: String(finding?.namespace || finding?.Namespace || ''),
    resource: String(finding?.resource || finding?.Resource || ''),
    message: String(finding?.message || finding?.Message || finding?.details || finding?.Value || ''),
  }));
}

function shouldIgnore(id, options) {
  return options.ignoredIds.includes(id) || options.ignoredPrefixes.some(prefix => id.startsWith(prefix));
}

function compareReports(goChecks, pluginChecks, options) {
  const ids = [...new Set([...goChecks.keys(), ...pluginChecks.keys()])]
    .filter(id => !shouldIgnore(id, options))
    .sort();
  const missingInPlugin = [];
  const missingInGo = [];
  const statusMismatches = [];
  const findingMismatches = [];
  const matches = [];

  for (const id of ids) {
    const goCheck = goChecks.get(id);
    const pluginCheck = pluginChecks.get(id);

    if (!goCheck) {
      missingInGo.push(id);
      continue;
    }
    if (!pluginCheck) {
      missingInPlugin.push(id);
      continue;
    }

    if (goCheck.status !== pluginCheck.status) {
      statusMismatches.push({ id, go: goCheck, plugin: pluginCheck });
      continue;
    }

    if (goCheck.findingCount !== pluginCheck.findingCount) {
      findingMismatches.push({ id, go: goCheck, plugin: pluginCheck });
      continue;
    }

    matches.push(id);
  }

  return { ids, missingInPlugin, missingInGo, statusMismatches, findingMismatches, matches };
}

function printList(title, items, formatter = item => `- ${item}`) {
  if (items.length === 0) {
    return;
  }

  console.log(`\n${title}`);
  for (const item of items) {
    console.log(formatter(item));
  }
}

function sampleFinding(check) {
  const finding = check.findings[0];
  if (!finding) {
    return '';
  }
  return [finding.namespace, finding.resource, finding.message].filter(Boolean).join(' | ');
}

const { goPath, pluginPath, options } = parseArgs(process.argv.slice(2));
const goReport = await readJson(goPath);
const pluginReport = await readJson(pluginPath);
const goChecks = normalizeReport(goReport, 'Go report');
const pluginChecks = normalizeReport(pluginReport, 'Headlamp report');
const result = compareReports(goChecks, pluginChecks, options);
const failingFindingMismatches = options.strictFindings ? result.findingMismatches : [];
const failed =
  result.missingInPlugin.length +
  result.missingInGo.length +
  result.statusMismatches.length +
  failingFindingMismatches.length;

console.log(`Compared ${result.ids.length} checks`);
console.log(`Go report:       ${path.basename(goPath)} (${goChecks.size} checks)`);
console.log(`Headlamp report: ${path.basename(pluginPath)} (${pluginChecks.size} checks)`);
console.log(`Ignored prefixes: ${options.ignoredPrefixes.length ? options.ignoredPrefixes.join(', ') : '(none)'}`);
console.log(`Ignored IDs: ${options.ignoredIds.length ? options.ignoredIds.join(', ') : '(none)'}`);
console.log(`Matches: ${result.matches.length}`);
console.log(`Missing in Headlamp: ${result.missingInPlugin.length}`);
console.log(`Missing in Go: ${result.missingInGo.length}`);
console.log(`Status mismatches: ${result.statusMismatches.length}`);
console.log(`Finding count mismatches: ${result.findingMismatches.length}${options.strictFindings ? '' : ' (informational)'}`);

if (options.showMatches) {
  printList('Matching checks', result.matches);
}

printList('Missing in Headlamp', result.missingInPlugin);
printList('Missing in Go', result.missingInGo);
printList('Status mismatches', result.statusMismatches, item => (
  `- ${item.id}: Go=${item.go.status} (${item.go.findingCount}) Headlamp=${item.plugin.status} (${item.plugin.findingCount})`
));
printList('Finding count mismatches', result.findingMismatches, item => (
  `- ${item.id}: Go=${item.go.findingCount} Headlamp=${item.plugin.findingCount}` +
  `${sampleFinding(item.go) ? `\n  Go sample: ${sampleFinding(item.go)}` : ''}` +
  `${sampleFinding(item.plugin) ? `\n  Headlamp sample: ${sampleFinding(item.plugin)}` : ''}`
));

if (failed > 0) {
  process.exit(1);
}
