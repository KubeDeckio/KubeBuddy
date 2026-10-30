import { describe, expect, it } from 'vitest';
import {
  isBuiltInNamespace,
  isSystemIsolationTaint,
  podContainers,
  rootUserIssue,
} from './checkHygiene';

describe('built-in resources and security evidence', () => {
  it.each(['default', 'kube-system', 'kube-public', 'kube-node-lease'])(
    'does not classify %s as namespace clutter',
    name => expect(isBuiltInNamespace(name)).toBe(true)
  );

  it('still checks application namespaces', () => {
    expect(isBuiltInNamespace('unused-app')).toBe(false);
  });

  it('only returns real containers, including init and ephemeral containers', () => {
    const web = { name: 'web' };
    const init = { name: 'init' };
    const debug = { name: 'debug' };
    expect(podContainers({ containers: [web] })).toEqual([web]);
    expect(podContainers({})).toEqual([]);
    expect(
      podContainers({
        containers: [web],
        initContainers: [init],
        ephemeralContainers: [debug],
      })
    ).toEqual([web, init, debug]);
  });

  it('only exempts the standard taint on a labelled AKS system node', () => {
    const taint = { key: 'CriticalAddonsOnly', value: 'true', effect: 'NoSchedule' };
    const labels = { 'kubernetes.azure.com/mode': 'system' };
    expect(isSystemIsolationTaint(taint, labels)).toBe(true);
    expect(isSystemIsolationTaint(taint, {})).toBe(false);
    expect(isSystemIsolationTaint(taint, { 'kubernetes.azure.com/mode': 'user' })).toBe(false);
    expect(isSystemIsolationTaint({ ...taint, key: 'custom' }, labels)).toBe(false);
    expect(isSystemIsolationTaint({ ...taint, effect: 'NoExecute' }, labels)).toBe(false);
  });

  it('respects effective container and pod security settings', () => {
    expect(rootUserIssue({ runAsUser: 1000 }, { runAsUser: 0 })).toBeNull();
    expect(rootUserIssue({ runAsUser: 0 }, { runAsUser: 1000 })).toBe('runs as UID 0');
    expect(rootUserIssue({}, { runAsNonRoot: true })).toBeNull();
    expect(rootUserIssue({ runAsNonRoot: true })).toBeNull();
    expect(rootUserIssue({ runAsNonRoot: false }, { runAsNonRoot: true })).toContain(
      'verify the image user'
    );
    expect(rootUserIssue()).toContain('verify the image user');
    expect(rootUserIssue({ runAsUser: 0, runAsNonRoot: true })).toBe('runs as UID 0');
  });
});
