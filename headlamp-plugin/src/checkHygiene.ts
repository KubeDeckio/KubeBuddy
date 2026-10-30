export function isBuiltInNamespace(name: string): boolean {
  return ['default', 'kube-system', 'kube-public', 'kube-node-lease'].includes(name);
}

export function podContainers<T>(spec: {
  containers?: T[];
  initContainers?: T[];
  ephemeralContainers?: T[];
}): T[] {
  return [
    ...(spec.containers || []),
    ...(spec.initContainers || []),
    ...(spec.ephemeralContainers || []),
  ];
}

export function isSystemIsolationTaint(
  taint: { key?: string; value?: string; effect?: string },
  labels: Record<string, unknown>
): boolean {
  const mode = labels['kubernetes.azure.com/mode'];
  return (
    typeof mode === 'string' &&
    mode.toLowerCase() === 'system' &&
    taint.key === 'CriticalAddonsOnly' &&
    taint.value === 'true' &&
    taint.effect === 'NoSchedule'
  );
}

type SecurityContext = { runAsUser?: unknown; runAsNonRoot?: boolean };

export function rootUserIssue(
  container: SecurityContext = {},
  pod: SecurityContext = {}
): string | null {
  const user = container.runAsUser ?? pod.runAsUser;
  if (user !== undefined && user !== null) {
    return Number(user) === 0 ? 'runs as UID 0' : null;
  }
  if ((container.runAsNonRoot ?? pod.runAsNonRoot) === true) {
    return null;
  }
  return 'has no explicit runAsUser or runAsNonRoot guarantee; verify the image user';
}
