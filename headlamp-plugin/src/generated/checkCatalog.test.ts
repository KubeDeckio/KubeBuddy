import { describe, expect, it } from 'vitest';
import { KUBERNETES_CHECKS } from './checkCatalog';

describe('generated check catalog', () => {
  it('includes the new risk checks with native handlers', () => {
    const expectedHandlers = new Map([
      ['SEC027', 'SEC027'],
      ['POD009', 'POD009'],
      ['PVC005', 'PVC005'],
      ['NET020', 'NET020'],
      ['RBAC005', 'RBAC005'],
      ['SEC028', 'SEC028'],
      ['SEC029', 'SEC029'],
      ['SEC030', 'SEC030'],
      ['WRK016', 'WRK016'],
      ['RBAC006', 'RBAC006'],
      ['POD010', 'POD010'],
      ['JOB003', 'JOB003'],
    ]);

    for (const [checkId, nativeHandler] of expectedHandlers) {
      expect(KUBERNETES_CHECKS).toContainEqual(
        expect.objectContaining({
          id: checkId,
          nativeHandler,
        })
      );
    }
  });

  it('does not include Prometheus-only checks in the browser catalog', () => {
    expect(KUBERNETES_CHECKS.some(check => check.sourceFile === 'prometheus.yaml')).toBe(false);
  });
});
