import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

const repoRoot = path.resolve(__dirname, '..');
const scriptPath = path.join(repoRoot, 'scripts', 'compare-go-report.mjs');

function writeJson(name: string, value: unknown): string {
  const dir = mkdtempSync(path.join(tmpdir(), 'kubebuddy-compare-'));
  const filePath = path.join(dir, name);

  writeFileSync(filePath, JSON.stringify(value, null, 2), 'utf8');

  return filePath;
}

function runCompare(goReport: unknown, pluginReport: unknown): { status: number | null; stdout: string; stderr: string } {
  const goPath = writeJson('go.json', goReport);
  const pluginPath = writeJson('plugin.json', pluginReport);

  return spawnSync(process.execPath, [scriptPath, goPath, pluginPath], {
    encoding: 'utf8',
  });
}

describe('compare-go-report', () => {
  it('matches Go JSON checks with Headlamp exported checks', () => {
    const output = runCompare(
      {
        checks: {
          NET001: {
            ID: 'NET001',
            Total: 1,
            Items: [{ Namespace: 'default', Resource: 'service/api', Message: 'No endpoints' }],
          },
        },
      },
      {
        checks: [
          {
            id: 'NET001',
            status: 'failed',
            findings: [{ namespace: 'default', resource: 'service/api', details: 'No endpoints' }],
          },
        ],
      }
    );

    expect(output.status).toBe(0);
    expect(output.stdout).toContain('Compared 1 checks');
    expect(output.stdout).toContain('Status mismatches: 0');
  });

  it('fails on status mismatches', () => {
    const output = runCompare(
      {
        checks: {
          NET001: {
            ID: 'NET001',
            Total: 1,
            Items: [{ Resource: 'service/api' }],
          },
        },
      },
      {
        checks: [
          {
            id: 'NET001',
            status: 'passed',
            findings: [],
          },
        ],
      }
    );

    expect(output.status).toBe(1);
    expect(output.stdout).toContain('Status mismatches: 1');
  });
});
