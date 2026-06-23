/*
 * KubeBuddy Headlamp plugin.
 */

import {
  K8s,
  registerAppBarAction,
  registerRoute,
  registerSidebarEntry,
} from '@kinvolk/headlamp-plugin/lib';
import { SectionBox } from '@kinvolk/headlamp-plugin/lib/CommonComponents';
import {
  Alert,
  Autocomplete,
  Box,
  Button,
  Checkbox,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  Divider,
  Drawer,
  FormControlLabel,
  IconButton,
  LinearProgress,
  Link,
  Paper,
  Stack,
  SvgIcon,
  Tab,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TableSortLabel,
  Tabs,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import type { Theme } from '@mui/material/styles';
import React from 'react';
import { useHistory, useLocation } from 'react-router-dom';
import {
  GeneratedCheck,
  GeneratedExpression,
  GeneratedPredicate,
  KUBERNETES_CHECKS,
} from './generated/checkCatalog';

type Severity = 'high' | 'warning' | 'medium' | 'low';
type CheckStatus = 'passed' | 'failed' | 'skipped';
type StatusFilter = CheckStatus | 'all';
type SeverityFilter = Severity | 'all';

type Finding = {
  resource: string;
  namespace?: string;
  kind?: string;
  apiVersion?: string;
  uid?: string;
  commandName?: string;
  commandNamespace?: string;
  details: string;
  link?: string;
};

type CheckResult = {
  id: string;
  name: string;
  category: string;
  section: string;
  severity: Severity;
  weight: number;
  description: string;
  failMessage: string;
  recommendation: string;
  recommendationHtml?: string;
  docs?: string;
  nativeHandler?: string;
  sourceFile: string;
  resourceKind: string;
  status: CheckStatus;
  skippedReason?: string;
  findings: Finding[];
};

type ResourceState<T = any> = {
  data: T[];
  error?: unknown;
  loading: boolean;
};

type Score = {
  value: number;
  passed: number;
  failed: number;
  skipped: number;
  total: number;
  failedWeight: number;
  totalWeight: number;
};

type ScanLogEntry = {
  id: number;
  timestamp: string;
  message: string;
  level: 'info' | 'success' | 'warning' | 'error';
  status?: CheckStatus;
  findings?: number;
};

type ResourceStates = Record<string, ResourceState>;
type KubeBuddyConfig = {
  useSystemNamespaceExclusions: boolean;
  additionalExcludedNamespaces: string[];
  excludedNamespaces: string[];
  excludedChecks: string[];
  trustedRegistries: string[];
  thresholds: {
    restartsWarning: number;
    restartsCritical: number;
    podAgeWarning: number;
    stuckJobHours: number;
    podsPerNodeCritical: number;
  };
};
type NativeHandler = (resources: ResourceStates, config: KubeBuddyConfig) => Finding[];

const EMPTY_RESOURCE_STATE: ResourceState = { data: [], loading: false };
const EMPTY_CHECKS: CheckResult[] = [];
const DEFAULT_EXCLUDED_NAMESPACES = [
  'kube-system',
  'kube-public',
  'kube-node-lease',
  'local-path-storage',
  'kube-flannel',
  'tigera-operator',
  'calico-system',
  'coredns',
  'aks-istio-system',
  'aks-command',
  'gatekeeper-system',
];
const DEFAULT_TRUSTED_REGISTRIES = ['mcr.microsoft.com/'];
const DEFAULT_THRESHOLDS: KubeBuddyConfig['thresholds'] = {
  restartsWarning: 3,
  restartsCritical: 5,
  podAgeWarning: 15,
  stuckJobHours: 2,
  podsPerNodeCritical: 90,
};

type ResourceStateEntry = ResourceState & {
  label: string;
};
const SCORE_UPDATED_EVENT = 'kubebuddy-score-updated';
const SCORE_FRESH_MS = 10 * 60 * 1000;
const CHECKS_PER_SCAN_STEP = 2;
const SCAN_STEP_DELAY_MS = 25;
const KUBEBUDDY_ICON = {
  width: 320,
  height: 320,
  body: '<g transform="translate(-59 -59)"><ellipse fill="currentColor" cx="181.8" cy="219.7" rx="16.9" ry="21.9"/><ellipse fill="currentColor" cx="254" cy="219.7" rx="16.9" ry="21.9"/><path fill="currentColor" d="M80.2,193.6v50.6c0,9,7.3,16.2,16.2,16.2h0v-83h0C87.5,177.4,80.2,184.7,80.2,193.6z"/><path fill="currentColor" d="M72.3,191.1c-4.6,0-8.4,3.8-8.4,8.4v35.4c0,4.6,3.8,8.4,8.4,8.4c0.3,0,0.6-0.3,0.6-0.6v-51C72.9,191.4,72.6,191.1,72.3,191.1z"/><path fill="currentColor" d="M341.8,177.4L341.8,177.4l0,83h0c9,0,16.2-7.3,16.2-16.2v-50.6C358,184.7,350.8,177.4,341.8,177.4z"/><path fill="currentColor" d="M366.1,191.1c-0.3,0-0.6,0.3-0.6,0.6v51c0,0.3,0.3,0.6,0.6,0.6c4.6,0,8.4-3.8,8.4-8.4v-35.4C374.4,194.9,370.7,191.1,366.1,191.1z"/><path fill="currentColor" d="M286.8,123l17.3-33.8c2.9-5.7,0.3-12.6-5.9-15.3c-6.2-2.7-13.6-0.2-16.5,5.5l0,0l-18.5,36c-1.7,3.3-5.1,5.4-8.8,5.4h-70.4c-3.5,0-6.6-1.9-8.2-5l-18.6-36.4c-2.9-5.7-10.3-8.2-16.5-5.5c-6.2,2.7-8.8,9.6-5.9,15.3l17.2,33.6c-27.3,7-47.5,31.8-47.5,61.3v68.2c0,35,28.3,63.3,63.3,63.3h25.3c2.6,0,4.6,2.1,4.6,4.6v40.9c0,6.6,7.3,10.5,12.8,6.8l90.4-60.3l0,0c19.5-10.8,32.7-31.6,32.7-55.4v-68.2C333.7,154.8,313.8,130.2,286.8,123z M304.9,247.6c0,20.6-16.7,37.3-37.3,37.3h-99.4c-20.6,0-37.3-16.7-37.3-37.3v-58.8c0-20.6,16.7-37.3,37.3-37.3h3.1c0,0.1,0,0.2,0,0.3c0,9.8,21.4,17.8,47.7,17.8c26.4,0,47.7-8,47.7-17.8c0-0.1,0-0.2,0-0.3h0.8c20.6,0,37.3,16.7,37.3,37.3V247.6z"/></g>',
};

type StoredScore = {
  value: number;
  failed: number;
  total: number;
  completedAt: string;
};

type StoredReport = {
  checks: CheckResult[];
  completedAt: string;
  excludedNamespaces?: string[];
  config?: KubeBuddyConfig;
};

type KubeBuddyReturnTarget = {
  checkId: string;
  section: string;
  findingKey: string;
};

function clusterKeyFromPath(pathname: string): string {
  const match = pathname.match(/^\/c\/([^/]+)/);
  return match ? decodeURIComponent(match[1]) : 'default';
}

function scoreStorageKey(clusterKey: string): string {
  return `kubebuddy:score:${clusterKey}`;
}

function reportStorageKey(clusterKey: string): string {
  return `kubebuddy:report:${clusterKey}`;
}

function excludedNamespacesStorageKey(clusterKey: string): string {
  return `kubebuddy:excluded-namespaces:${clusterKey}`;
}

function configStorageKey(clusterKey: string): string {
  return `kubebuddy:config:${clusterKey}`;
}

function returnTargetStorageKey(clusterKey: string): string {
  return `kubebuddy:return-target:${clusterKey}`;
}

function normalizeNamespaceList(namespaces: string[]): string[] {
  return Array.from(
    new Set(
      namespaces
        .map(namespace => namespace.trim().toLowerCase())
        .filter(Boolean)
    )
  ).sort();
}

function readExcludedNamespaces(clusterKey: string): string[] {
  try {
    const value = window.localStorage.getItem(excludedNamespacesStorageKey(clusterKey));
    if (!value) {
      return DEFAULT_EXCLUDED_NAMESPACES;
    }

    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed)) {
      return DEFAULT_EXCLUDED_NAMESPACES;
    }

    return normalizeNamespaceList(parsed);
  } catch {
    return DEFAULT_EXCLUDED_NAMESPACES;
  }
}

function storeExcludedNamespaces(clusterKey: string, namespaces: string[]): void {
  window.localStorage.setItem(excludedNamespacesStorageKey(clusterKey), JSON.stringify(normalizeNamespaceList(namespaces)));
}

function canonicalContainerImageReference(image: string): string {
  const trimmed = image.trim();
  const withoutDigest = trimmed.split('@')[0];
  const firstSegment = withoutDigest.split('/')[0];
  const hasPath = withoutDigest.includes('/');

  if (!trimmed || !firstSegment) {
    return '';
  }

  if (hasPath && (firstSegment.includes('.') || firstSegment.includes(':') || firstSegment === 'localhost')) {
    return trimmed;
  }

  if (trimmed.includes('/')) {
    return `docker.io/${trimmed}`;
  }

  return `docker.io/library/${trimmed}`;
}

function imageRegistryPrefix(image: string): string {
  const canonicalImage = canonicalContainerImageReference(image);
  const segments = canonicalImage.split('/');

  if (!segments[0]) {
    return '';
  }

  if (segments[0] === 'docker.io' && segments[1]) {
    return `docker.io/${segments[1]}/`;
  }

  return `${segments[0]}/`;
}

function normalizeRegistryPrefix(registry: string): string {
  const trimmed = registry.trim();
  const withoutTrailingSlash = trimmed.replace(/\/+$/, '');
  const lastSegment = withoutTrailingSlash.split('/').pop() || '';

  if (!withoutTrailingSlash) {
    return '';
  }

  if (
    (withoutTrailingSlash.includes('/') && !withoutTrailingSlash.split('/')[0].includes('.') && !withoutTrailingSlash.split('/')[0].includes(':')) ||
    withoutTrailingSlash.includes('@') ||
    lastSegment.includes(':')
  ) {
    return imageRegistryPrefix(withoutTrailingSlash);
  }

  return `${withoutTrailingSlash}/`;
}

function normalizeRegistries(registries: string[]): string[] {
  return Array.from(
    new Set(
      registries
        .map(normalizeRegistryPrefix)
        .filter(Boolean)
    )
  ).sort();
}

function defaultKubeBuddyConfig(): KubeBuddyConfig {
  return {
    useSystemNamespaceExclusions: true,
    additionalExcludedNamespaces: [],
    excludedNamespaces: DEFAULT_EXCLUDED_NAMESPACES,
    excludedChecks: [],
    trustedRegistries: DEFAULT_TRUSTED_REGISTRIES,
    thresholds: { ...DEFAULT_THRESHOLDS },
  };
}

function effectiveExcludedNamespaces(config: Pick<KubeBuddyConfig, 'useSystemNamespaceExclusions' | 'additionalExcludedNamespaces'>): string[] {
  return normalizeNamespaceList([
    ...(config.useSystemNamespaceExclusions ? DEFAULT_EXCLUDED_NAMESPACES : []),
    ...config.additionalExcludedNamespaces,
  ]);
}

function normalizeKubeBuddyConfig(config: Partial<KubeBuddyConfig>): KubeBuddyConfig {
  const defaults = defaultKubeBuddyConfig();
  const legacyExcluded = Array.isArray(config.excludedNamespaces)
    ? normalizeNamespaceList(config.excludedNamespaces)
    : defaults.excludedNamespaces;
  const useSystemNamespaceExclusions =
    typeof config.useSystemNamespaceExclusions === 'boolean'
      ? config.useSystemNamespaceExclusions
      : DEFAULT_EXCLUDED_NAMESPACES.every(namespace => legacyExcluded.includes(namespace));
  const additionalExcludedNamespaces = Array.isArray(config.additionalExcludedNamespaces)
    ? normalizeNamespaceList(config.additionalExcludedNamespaces)
    : normalizeNamespaceList(legacyExcluded.filter(namespace => !DEFAULT_EXCLUDED_NAMESPACES.includes(namespace)));
  const normalized: KubeBuddyConfig = {
    useSystemNamespaceExclusions,
    additionalExcludedNamespaces,
    excludedNamespaces: effectiveExcludedNamespaces({ useSystemNamespaceExclusions, additionalExcludedNamespaces }),
    excludedChecks: Array.isArray(config.excludedChecks)
      ? Array.from(new Set(config.excludedChecks.map(id => id.trim().toUpperCase()).filter(Boolean))).sort()
      : defaults.excludedChecks,
    trustedRegistries: Array.isArray(config.trustedRegistries)
      ? normalizeRegistries(config.trustedRegistries)
      : defaults.trustedRegistries,
    thresholds: {
      ...defaults.thresholds,
      ...(config.thresholds || {}),
    },
  };

  return normalized;
}

function readKubeBuddyConfig(clusterKey: string): KubeBuddyConfig {
  const defaults = defaultKubeBuddyConfig();

  try {
    const value = window.localStorage.getItem(configStorageKey(clusterKey));
    if (!value) {
      return normalizeKubeBuddyConfig({
        ...defaults,
        excludedNamespaces: readExcludedNamespaces(clusterKey),
      });
    }

    const parsed = JSON.parse(value) as Partial<KubeBuddyConfig>;
    return normalizeKubeBuddyConfig(parsed);
  } catch {
    return defaults;
  }
}

function storeKubeBuddyConfig(clusterKey: string, config: KubeBuddyConfig): void {
  const normalized = normalizeKubeBuddyConfig({
    ...config,
    thresholds: {
      restartsWarning: Number(config.thresholds.restartsWarning) || DEFAULT_THRESHOLDS.restartsWarning,
      restartsCritical: Number(config.thresholds.restartsCritical) || DEFAULT_THRESHOLDS.restartsCritical,
      podAgeWarning: Number(config.thresholds.podAgeWarning) || DEFAULT_THRESHOLDS.podAgeWarning,
      stuckJobHours: Number(config.thresholds.stuckJobHours) || DEFAULT_THRESHOLDS.stuckJobHours,
      podsPerNodeCritical: Number(config.thresholds.podsPerNodeCritical) || DEFAULT_THRESHOLDS.podsPerNodeCritical,
    },
  });

  window.localStorage.setItem(configStorageKey(clusterKey), JSON.stringify(normalized));
  storeExcludedNamespaces(clusterKey, normalized.excludedNamespaces);
}

function readStoredScore(clusterKey: string): StoredScore | null {
  try {
    const value = window.localStorage.getItem(scoreStorageKey(clusterKey));
    if (!value) {
      return null;
    }

    const parsed = JSON.parse(value) as Partial<StoredScore>;
    if (
      typeof parsed.value !== 'number' ||
      typeof parsed.failed !== 'number' ||
      typeof parsed.total !== 'number' ||
      typeof parsed.completedAt !== 'string'
    ) {
      return null;
    }

    return parsed as StoredScore;
  } catch {
    return null;
  }
}

function readStoredReport(clusterKey: string): StoredReport | null {
  try {
    const value = window.localStorage.getItem(reportStorageKey(clusterKey));
    if (!value) {
      return null;
    }

    const parsed = JSON.parse(value) as Partial<StoredReport>;
    if (!Array.isArray(parsed.checks) || typeof parsed.completedAt !== 'string') {
      return null;
    }

    return parsed as StoredReport;
  } catch {
    return null;
  }
}

function storeScore(clusterKey: string, checks: CheckResult[]): StoredScore {
  const score = scoreChecks(checks);
  const storedScore: StoredScore = {
    value: score.value,
    failed: score.failed,
    total: score.total,
    completedAt: new Date().toISOString(),
  };

  window.localStorage.setItem(scoreStorageKey(clusterKey), JSON.stringify(storedScore));
  window.dispatchEvent(new CustomEvent(SCORE_UPDATED_EVENT, { detail: { clusterKey } }));

  return storedScore;
}

function storeReport(clusterKey: string, checks: CheckResult[], config: KubeBuddyConfig): StoredReport {
  const storedReport: StoredReport = {
    checks,
    completedAt: new Date().toISOString(),
    excludedNamespaces: normalizeNamespaceList(config.excludedNamespaces),
    config,
  };

  window.localStorage.setItem(reportStorageKey(clusterKey), JSON.stringify(storedReport));
  storeScore(clusterKey, checks);

  return storedReport;
}

function csvValue(value: unknown): string {
  const text = value === null || value === undefined ? '' : String(value);
  return `"${text.replace(/"/g, '""')}"`;
}

function exportReportCsv(clusterKey: string, report: StoredReport): void {
  const headers = [
    'cluster',
    'completed_at',
    'check_id',
    'check_name',
    'section',
    'severity',
    'status',
    'finding_count',
    'resource',
    'namespace',
    'kind',
    'api_version',
    'details',
    'recommendation',
    'docs',
  ];
  const rows = report.checks.flatMap(check => {
    const base = [
      clusterKey,
      report.completedAt,
      check.id,
      check.name,
      reportSectionLabel(check.section),
      check.severity,
      check.status,
      check.findings.length,
    ];

    if (check.findings.length === 0) {
      return [[
        ...base,
        '',
        '',
        '',
        '',
        check.skippedReason || '',
        check.recommendation,
        check.docs || '',
      ]];
    }

    return check.findings.map(finding => [
      ...base,
      finding.resource,
      finding.namespace || '',
      finding.kind || '',
      finding.apiVersion || '',
      finding.details,
      check.recommendation,
      check.docs || '',
    ]);
  });

  const csv = [
    headers.map(csvValue).join(','),
    ...rows.map(row => row.map(csvValue).join(',')),
  ].join('\r\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  const safeCluster = clusterKey.replace(/[^a-z0-9_-]+/gi, '-').replace(/^-+|-+$/g, '') || 'cluster';
  const completedAt = report.completedAt.replace(/[:.]/g, '-');

  link.href = url;
  link.download = `kubebuddy-${safeCluster}-${completedAt}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function findingKey(finding: Finding): string {
  return [
    finding.resource,
    finding.namespace || '',
    finding.kind || '',
    finding.details,
  ].join('\u001f');
}

function storeReturnTarget(clusterKey: string, target: KubeBuddyReturnTarget): void {
  window.sessionStorage.setItem(returnTargetStorageKey(clusterKey), JSON.stringify(target));
}

function consumeReturnTarget(clusterKey: string): KubeBuddyReturnTarget | null {
  try {
    const value = window.sessionStorage.getItem(returnTargetStorageKey(clusterKey));
    if (!value) {
      return null;
    }

    window.sessionStorage.removeItem(returnTargetStorageKey(clusterKey));
    const parsed = JSON.parse(value) as Partial<KubeBuddyReturnTarget>;
    if (
      typeof parsed.checkId !== 'string' ||
      typeof parsed.section !== 'string' ||
      typeof parsed.findingKey !== 'string'
    ) {
      return null;
    }

    return parsed as KubeBuddyReturnTarget;
  } catch {
    return null;
  }
}

function isFreshScore(score: StoredScore): boolean {
  return Date.now() - new Date(score.completedAt).getTime() <= SCORE_FRESH_MS;
}

function formatScoreAge(score: StoredScore): string {
  const ageMs = Math.max(0, Date.now() - new Date(score.completedAt).getTime());
  const minutes = Math.floor(ageMs / 60000);

  if (minutes < 1) {
    return 'just now';
  }

  if (minutes < 60) {
    return `${minutes}m ago`;
  }

  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours}h ago`;
  }

  return `${Math.floor(hours / 24)}d ago`;
}

function scanLogEntry(
  message: string,
  level: ScanLogEntry['level'] = 'info',
  extra: Pick<ScanLogEntry, 'status' | 'findings'> = {}
): ScanLogEntry {
  return {
    id: Date.now() + Math.random(),
    timestamp: new Date().toLocaleTimeString(),
    message,
    level,
    ...extra,
  };
}

function errorField(error: unknown, field: string): unknown {
  if (!error || typeof error !== 'object') {
    return undefined;
  }

  return (error as Record<string, unknown>)[field];
}

function formatResourceError(label: string, error: unknown): string {
  if (error instanceof Error) {
    const status = errorField(error, 'status') || errorField(error, 'statusCode') || errorField(error, 'code');
    const body = errorField(error, 'body') || errorField(error, 'response') || errorField(error, 'data');
    const detail = typeof body === 'string' ? body : body ? JSON.stringify(body) : '';

    return `${label}: ${error.name}: ${error.message}${status ? ` (${status})` : ''}${detail ? ` - ${detail}` : ''}`;
  }

  if (typeof error === 'string') {
    return `${label}: ${error}`;
  }

  if (error && typeof error === 'object') {
    const message = errorField(error, 'message') || errorField(error, 'statusText') || errorField(error, 'reason');
    const status = errorField(error, 'status') || errorField(error, 'statusCode') || errorField(error, 'code');

    return `${label}: ${message || 'Unable to load resource list'}${status ? ` (${status})` : ''} - ${JSON.stringify(error)}`;
  }

  return `${label}: Unknown resource loading error`;
}

function errorStatus(error: unknown): string {
  const status =
    errorField(error, 'status') ||
    errorField(error, 'statusCode') ||
    errorField(error, 'code');

  return String(status || '');
}

function isOptionalMissingApi(label: string, error: unknown): boolean {
  return ['Gateways', 'HTTPRoutes'].includes(label) && errorStatus(error) === '404';
}

function logLevelColor(level: ScanLogEntry['level']): string {
  if (level === 'success') {
    return '#7ee787';
  }
  if (level === 'warning') {
    return '#ffd166';
  }
  if (level === 'error') {
    return '#ff7b72';
  }
  return 'text.secondary';
}

function resultLogLevel(result: CheckResult): ScanLogEntry['level'] {
  if (result.status === 'failed') {
    return 'error';
  }
  if (result.status === 'skipped') {
    return 'warning';
  }
  return 'success';
}

function resultLogMessage(result: CheckResult): string {
  if (result.status === 'skipped') {
    return `${result.id} skipped - ${result.skippedReason || 'not available in this plugin'}.`;
  }

  return `${result.id} checked - ${result.findings.length} finding${result.findings.length === 1 ? '' : 's'}.`;
}

function KubeBuddyLogoMark() {
  return (
    <Box
      aria-hidden="true"
      component="svg"
      viewBox="0 0 432 432"
      sx={{ display: 'block', height: 18, width: 18 }}
    >
      <ellipse fill="currentColor" cx="181.8" cy="219.7" rx="16.9" ry="21.9" />
      <ellipse fill="currentColor" cx="254" cy="219.7" rx="16.9" ry="21.9" />
      <path
        fill="currentColor"
        d="M80.2,193.6v50.6c0,9,7.3,16.2,16.2,16.2h0v-83h0C87.5,177.4,80.2,184.7,80.2,193.6z"
      />
      <path
        fill="currentColor"
        d="M72.3,191.1c-4.6,0-8.4,3.8-8.4,8.4v35.4c0,4.6,3.8,8.4,8.4,8.4c0.3,0,0.6-0.3,0.6-0.6v-51C72.9,191.4,72.6,191.1,72.3,191.1z"
      />
      <path
        fill="currentColor"
        d="M341.8,177.4L341.8,177.4l0,83h0c9,0,16.2-7.3,16.2-16.2v-50.6C358,184.7,350.8,177.4,341.8,177.4z"
      />
      <path
        fill="currentColor"
        d="M366.1,191.1c-0.3,0-0.6,0.3-0.6,0.6v51c0,0.3,0.3,0.6,0.6,0.6c4.6,0,8.4-3.8,8.4-8.4v-35.4C374.4,194.9,370.7,191.1,366.1,191.1z"
      />
      <path
        fill="currentColor"
        d="M286.8,123l17.3-33.8c2.9-5.7,0.3-12.6-5.9-15.3c-6.2-2.7-13.6-0.2-16.5,5.5l0,0l-18.5,36c-1.7,3.3-5.1,5.4-8.8,5.4h-70.4c-3.5,0-6.6-1.9-8.2-5l-18.6-36.4c-2.9-5.7-10.3-8.2-16.5-5.5c-6.2,2.7-8.8,9.6-5.9,15.3l17.2,33.6c-27.3,7-47.5,31.8-47.5,61.3v68.2c0,35,28.3,63.3,63.3,63.3h25.3c2.6,0,4.6,2.1,4.6,4.6v40.9c0,6.6,7.3,10.5,12.8,6.8l90.4-60.3l0,0c19.5-10.8,32.7-31.6,32.7-55.4v-68.2C333.7,154.8,313.8,130.2,286.8,123z M304.9,247.6c0,20.6-16.7,37.3-37.3,37.3h-99.4c-20.6,0-37.3-16.7-37.3-37.3v-58.8c0-20.6,16.7-37.3,37.3-37.3h3.1c0,0.1,0,0.2,0,0.3c0,9.8,21.4,17.8,47.7,17.8c26.4,0,47.7-8,47.7-17.8c0-0.1,0-0.2,0-0.3h0.8c20.6,0,37.3,16.7,37.3,37.3V247.6z"
      />
    </Box>
  );
}

function useResourceList<T>(hookResult: [T[] | null, unknown]): ResourceState<T> {
  const [items, error] = hookResult;

  return {
    data: items || [],
    error,
    loading: !items && !error,
  };
}

function json(resource: any): any {
  return resource?.jsonData || resource;
}

function name(resource: any): string {
  return resource?.getName?.() || resource?.metadata?.name || resource?.jsonData?.metadata?.name || 'Unknown';
}

function namespace(resource: any): string | undefined {
  return resource?.getNamespace?.() || resource?.metadata?.namespace || resource?.jsonData?.metadata?.namespace;
}

function namespaceOrName(resource: any): string | undefined {
  const resourceNamespace = namespace(resource);
  if (resourceNamespace) {
    return resourceNamespace;
  }

  if (kind(resource) === 'Namespace') {
    return name(resource);
  }

  return undefined;
}

function kind(resource: any): string | undefined {
  return resource?.kind || resource?.jsonData?.kind || resource?.metadata?.kind || resource?.jsonData?.metadata?.kind;
}

function apiVersion(resource: any): string | undefined {
  return resource?.apiVersion || resource?.jsonData?.apiVersion;
}

function uid(resource: any): string | undefined {
  return resource?.metadata?.uid || resource?.jsonData?.metadata?.uid;
}

function link(resource: any): string | undefined {
  return resource?.getDetailsLink?.();
}

function DocsIcon(props: React.ComponentProps<typeof SvgIcon>) {
  return (
    <SvgIcon fontSize="small" viewBox="0 0 24 24" {...props}>
      <path d="M14 2H6c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V8l-6-6Zm-1 7V3.5L18.5 9H13Zm-5 4h8v2H8v-2Zm0 4h8v2H8v-2Zm0-8h3v2H8V9Z" />
    </SvgIcon>
  );
}

function ExpandDownIcon(props: React.ComponentProps<typeof SvgIcon>) {
  return (
    <SvgIcon fontSize="small" viewBox="0 0 24 24" {...props}>
      <path d="M7.4 8.6 12 13.2l4.6-4.6L18 10l-6 6-6-6 1.4-1.4Z" />
    </SvgIcon>
  );
}

function namespaceSet(namespaces: string[]): Set<string> {
  return new Set(normalizeNamespaceList(namespaces));
}

function filterResourceState<T>(state: ResourceState<T>, excludedNamespaces: Set<string>): ResourceState<T> {
  if (!excludedNamespaces.size) {
    return state;
  }

  return {
    ...state,
    data: state.data.filter(item => {
      const itemNamespace = namespaceOrName(item);
      return !itemNamespace || !excludedNamespaces.has(itemNamespace.toLowerCase());
    }),
  };
}

function finding(resource: any, details: string): Finding {
  return {
    resource: name(resource),
    namespace: namespace(resource),
    kind: kind(resource),
    apiVersion: apiVersion(resource),
    uid: uid(resource),
    commandName: name(resource),
    commandNamespace: namespace(resource),
    details,
    link: link(resource),
  };
}

function restartCount(pod: any): number {
  return (json(pod)?.status?.containerStatuses || []).reduce(
    (total: number, status: any) => total + (status.restartCount || 0),
    0
  );
}

function podImages(pod: any): string[] {
  const spec = json(pod)?.spec || {};
  return [...(spec.initContainers || []), ...(spec.containers || [])]
    .map((container: any) => container.image)
    .filter(Boolean);
}

function containers(pod: any, includeInit = true): any[] {
  const spec = json(pod)?.spec || {};
  return includeInit ? [...(spec.initContainers || []), ...(spec.containers || [])] : spec.containers || [];
}

function selectorKey(selector: unknown): string {
  if (!selector || typeof selector !== 'object') {
    return '';
  }
  return Object.entries(selector as Record<string, unknown>)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}=${value}`)
    .join(',');
}

function selectorMatches(selector: unknown, labels: unknown): boolean {
  if (!selector || !labels || typeof selector !== 'object' || typeof labels !== 'object') {
    return false;
  }
  return Object.entries(selector as Record<string, unknown>).every(
    ([key, value]) => (labels as Record<string, unknown>)[key] === value
  );
}

function workloadTemplate(workload: any): any {
  return json(workload)?.spec?.template || {};
}

function workloadSelector(workload: any): unknown {
  return json(workload)?.spec?.selector?.matchLabels;
}

function workloadLabels(workload: any): unknown {
  return workloadTemplate(workload)?.metadata?.labels;
}

function allWorkloads(resources: ResourceStates): any[] {
  return [
    ...resources.deployment.data,
    ...resources.daemonset.data,
    ...resources.statefulset.data,
  ];
}

function workloadContainers(workload: any): any[] {
  return workloadTemplate(workload)?.spec?.containers || [];
}

function hasProbe(container: any): boolean {
  return !!container.readinessProbe && !!container.livenessProbe;
}

function objectLabels(resource: any): Record<string, unknown> {
  return json(resource)?.metadata?.labels || {};
}

function objectAnnotations(resource: any): Record<string, unknown> {
  return json(resource)?.metadata?.annotations || {};
}

function serviceSelector(service: any): unknown {
  return json(service)?.spec?.selector;
}

function hasResource(container: any, mode: 'requests' | 'limits', resource: 'cpu' | 'memory'): boolean {
  return !!container?.resources?.[mode]?.[resource];
}

function serviceAccountName(pod: any): string {
  return json(pod)?.spec?.serviceAccountName || 'default';
}

function daysSince(timestamp?: string): number | null {
  if (!timestamp) {
    return null;
  }

  const time = new Date(timestamp).getTime();
  if (Number.isNaN(time)) {
    return null;
  }

  return Math.floor((Date.now() - time) / 86400000);
}

function nodeReady(node: any): boolean {
  return (json(node)?.status?.conditions || []).some(
    (condition: any) => condition.type === 'Ready' && condition.status === 'True'
  );
}

function normalizeSeverity(severity: string): Severity {
  const normalized = severity.toLowerCase();
  if (normalized === 'high' || normalized === 'error') {
    return 'high';
  }
  if (normalized === 'warning') {
    return 'warning';
  }
  if (normalized === 'medium') {
    return 'medium';
  }
  return 'low';
}

function scoreChecks(checks: CheckResult[]): Score {
  const scoreableChecks = checks.filter(check => check.status !== 'skipped');
  const failedChecks = scoreableChecks.filter(check => check.status === 'failed');
  const totalWeight = scoreableChecks.reduce((total, check) => total + check.weight, 0);
  const failedWeight = failedChecks.reduce((total, check) => total + check.weight, 0);
  const value = totalWeight === 0 ? 100 : Math.round(100 - (failedWeight / totalWeight) * 100);

  return {
    value,
    passed: scoreableChecks.length - failedChecks.length,
    failed: failedChecks.length,
    skipped: checks.length - scoreableChecks.length,
    total: scoreableChecks.length,
    failedWeight,
    totalWeight,
  };
}

function scoreColor(score: number): 'success' | 'warning' | 'error' {
  if (score >= 90) {
    return 'success';
  }
  if (score >= 70) {
    return 'warning';
  }
  return 'error';
}

function scoreBadgeColor(score: number, theme: Theme): string {
  if (score >= 90) {
    return theme.palette.success.main;
  }

  if (score >= 70) {
    return theme.palette.warning.main;
  }

  return theme.palette.error.main;
}

function scoreBadgeContrastColor(score: number, theme: Theme): string {
  if (score >= 90) {
    return theme.palette.success.contrastText;
  }

  if (score >= 70) {
    return theme.palette.warning.contrastText;
  }

  return theme.palette.error.contrastText;
}

function severityColor(severity: Severity): 'error' | 'warning' | 'info' | 'success' {
  if (severity === 'high') {
    return 'error';
  }
  if (severity === 'warning' || severity === 'medium') {
    return 'warning';
  }
  return 'info';
}

function normalizeResourceKind(kind: string): string {
  return kind.toLowerCase().replace(/\s+/g, '');
}

function getResourcesForCheck(check: GeneratedCheck, resources: ResourceStates): any[] | null {
  return resources[normalizeResourceKind(check.resourceKind)]?.data || null;
}

function resolveExpression(item: any, expression?: GeneratedExpression): unknown {
  if (!expression) {
    return undefined;
  }
  if (expression.path) {
    return resolvePath(item, expression.path);
  }
  if ('value' in expression) {
    return expression.value;
  }
  if (expression.count_where) {
    const items = toArray(resolvePath(item, expression.count_where.path));
    return items.filter(candidate => evaluatePredicate(candidate, expression.count_where!.where)).length;
  }
  if (expression.coalesce?.length) {
    for (const candidate of expression.coalesce) {
      const value = resolveExpression(item, candidate);
      if (value !== undefined && value !== null) {
        return value;
      }
    }
    return undefined;
  }
  if (expression.any?.length) {
    return expression.any.some(predicate => evaluatePredicate(item, predicate));
  }
  if (expression.all?.length) {
    return expression.all.every(predicate => evaluatePredicate(item, predicate));
  }
  return undefined;
}

function evaluatePredicate(item: any, predicate: GeneratedPredicate): boolean {
  if (predicate.any?.length) {
    return predicate.any.some(child => evaluatePredicate(item, child));
  }
  if (predicate.all?.length) {
    return predicate.all.every(child => evaluatePredicate(item, child));
  }

  const actual = resolvePath(item, predicate.path || '');
  return !evaluateOperator(predicate.operator || 'exists', actual, predicate.expected);
}

function resolvePath(item: any, path: string): unknown {
  let current = item;

  for (const part of path.split('.').filter(Boolean)) {
    const flatten = part.endsWith('[]');
    const field = part.replace(/\[\]$/, '');

    current = lookupField(current, field);
    if (current === undefined || current === null) {
      return current;
    }
    if (flatten) {
      current = toArray(current);
    }
  }

  return current;
}

function lookupField(item: any, field: string): unknown {
  if (Array.isArray(item)) {
    const values = item.flatMap(candidate => {
      const value = lookupField(candidate, field);
      return Array.isArray(value) ? value : value === undefined ? [] : [value];
    });
    return values.length > 0 ? values : undefined;
  }

  if (item && typeof item === 'object') {
    const key = Object.keys(item).find(candidate => candidate.toLowerCase() === field.toLowerCase());
    return key ? item[key] : undefined;
  }

  return undefined;
}

function evaluateOperator(operator: string, actual: unknown, expected: unknown): boolean {
  const expectedValues = normalizeExpected(expected);

  switch (operator) {
    case 'equals':
      return !matchesAny(actual, expectedValues);
    case 'not_equals':
      return matchesAny(actual, expectedValues);
    case 'contains':
      return !containsAny(actual, expectedValues);
    case 'not_contains':
      return containsAny(actual, expectedValues);
    case 'exists':
      return actual === undefined || actual === null;
    case 'missing':
      return actual !== undefined && actual !== null;
    case 'greater_than':
      return !compareNumber(actual, expectedValues[0], (a, b) => a > b);
    case 'greater_than_or_equal':
      return !compareNumber(actual, expectedValues[0], (a, b) => a >= b);
    case 'less_than':
      return !compareNumber(actual, expectedValues[0], (a, b) => a < b);
    case 'less_than_or_equal':
      return !compareNumber(actual, expectedValues[0], (a, b) => a <= b);
    default:
      return false;
  }
}

function normalizeExpected(expected: unknown): unknown[] {
  if (typeof expected === 'string' && expected.includes(',')) {
    return expected.split(',').map(value => (value === 'null' ? null : value));
  }
  return Array.isArray(expected) ? expected : [expected];
}

function matchesAny(actual: unknown, expectedValues: unknown[]): boolean {
  const actualValues = toArray(actual);
  return actualValues.some(actualValue =>
    expectedValues.some(expectedValue => String(actualValue) === String(expectedValue))
  );
}

function containsAny(actual: unknown, expectedValues: unknown[]): boolean {
  return toArray(actual).some(actualValue =>
    expectedValues.some(expectedValue => String(actualValue).includes(String(expectedValue)))
  );
}

function compareNumber(actual: unknown, expected: unknown, compare: (actual: number, expected: number) => boolean) {
  const actualNumber = Number(toArray(actual)[0]);
  const expectedNumber = Number(expected);
  return Number.isFinite(actualNumber) && Number.isFinite(expectedNumber) && compare(actualNumber, expectedNumber);
}

function toArray(value: unknown): unknown[] {
  if (value === undefined || value === null) {
    return [];
  }
  return Array.isArray(value) ? value : [value];
}

function valueDetails(check: GeneratedCheck, value: unknown) {
  const path = check.value?.path || check.operator || 'value';
  const display = Array.isArray(value) ? value.join(', ') : String(value ?? 'missing');
  return `${path}: ${display}`;
}

function resultFromCheck(
  check: GeneratedCheck,
  findings: Finding[],
  status: CheckStatus = findings.length > 0 ? 'failed' : 'passed',
  skippedReason?: string
): CheckResult {
  return {
    id: check.id,
    name: check.name,
    category: check.category,
    section: check.section,
    severity: normalizeSeverity(check.severity),
    weight: check.weight,
    description: check.description,
    failMessage: check.failMessage,
    recommendation: check.recommendation,
    recommendationHtml: check.recommendationHtml,
    docs: check.url,
    nativeHandler: check.nativeHandler,
    sourceFile: check.sourceFile,
    resourceKind: check.resourceKind,
    status,
    skippedReason,
    findings,
  };
}

function emptyHandler(): Finding[] {
  return [];
}

function podSecurityHandlers(resources: ResourceStates): Record<string, Finding[]> {
  const pods = resources.pod.data;
  return {
    SEC002: pods.filter(pod => json(pod)?.spec?.hostPID || json(pod)?.spec?.hostNetwork).map(pod => finding(pod, 'hostPID or hostNetwork enabled')),
    SEC003: pods.flatMap(pod => containers(pod).filter(container => container?.securityContext?.runAsUser === 0 || json(pod)?.spec?.securityContext?.runAsUser === 0).map(container => finding(pod, `Container ${container.name} can run as root`))),
    SEC004: pods.flatMap(pod => containers(pod).filter(container => container?.securityContext?.privileged).map(container => finding(pod, `Container ${container.name} is privileged`))),
    SEC005: pods.filter(pod => json(pod)?.spec?.hostIPC).map(pod => finding(pod, 'hostIPC enabled')),
    SEC006: pods.flatMap(pod => containers(pod, false).filter(container => {
      const context = container?.securityContext;
      return !context || context.runAsNonRoot !== true || context.readOnlyRootFilesystem !== true || context.allowPrivilegeEscalation !== false;
    }).map(container => finding(pod, `Container ${container.name} missing hardened securityContext`))),
    SEC008: pods.flatMap(pod => containers(pod).flatMap(container => (container.env || []).filter((env: any) => env?.valueFrom?.secretKeyRef?.name).map((env: any) => finding(pod, `Secret exposed through env ${env.name} in ${container.name}`)))),
    SEC009: pods.flatMap(pod => containers(pod, false).filter(container => !(container?.securityContext?.capabilities?.drop || []).includes('ALL')).map(container => finding(pod, `Container ${container.name} does not drop ALL capabilities`))),
    SEC010: pods.flatMap(pod => (json(pod)?.spec?.volumes || []).filter((volume: any) => volume.hostPath?.path).map((volume: any) => finding(pod, `hostPath volume ${volume.name}: ${volume.hostPath.path}`))),
    SEC011: pods.flatMap(pod => containers(pod, false).filter(container => container?.securityContext?.runAsUser === 0).map(container => finding(pod, `Container ${container.name} runs as UID 0`))),
    SEC012: pods.flatMap(pod => containers(pod, false).filter(container => (container?.securityContext?.capabilities?.add || []).length > 0).map(container => finding(pod, `Container ${container.name} adds capabilities`))),
    SEC013: pods.flatMap(pod => (json(pod)?.spec?.volumes || []).filter((volume: any) => volume.emptyDir).map((volume: any) => finding(pod, `emptyDir volume ${volume.name}`))),
    SEC016: pods.flatMap(pod => containers(pod).filter(container => container?.securityContext?.windowsOptions?.hostProcess).map(container => finding(pod, `Windows HostProcess container ${container.name}`))),
    SEC017: pods.flatMap(pod => containers(pod).filter(container => container?.securityContext?.procMount === 'Unmasked').map(container => finding(pod, `Container ${container.name} uses Unmasked procMount`))),
    SEC019: pods.flatMap(pod => Object.entries(objectAnnotations(pod)).filter(([key, value]) => key.startsWith('container.apparmor.security.beta.kubernetes.io/') && !['runtime/default'].includes(String(value)) && !String(value).startsWith('localhost/')).map(([, value]) => finding(pod, `Unsupported AppArmor value ${value}`))),
    SEC020: pods.flatMap(pod => containers(pod).filter(container => !container?.securityContext?.seccompProfile?.type && !json(pod)?.spec?.securityContext?.seccompProfile?.type).map(container => finding(pod, `Container ${container.name} has no seccomp profile`))),
    SEC021: pods.flatMap(pod => containers(pod).filter(container => (container.ports || []).some((port: any) => Number(port.hostPort) > 0)).map(container => finding(pod, `Container ${container.name} uses hostPort`))),
    SEC022: pods.filter(pod => serviceAccountName(pod) === 'default').map(pod => finding(pod, 'Uses default ServiceAccount')),
    SEC023: pods.flatMap(pod => containers(pod).filter(container => Object.keys(container.resources || {}).length === 0).map(container => finding(pod, `Container ${container.name} has no resources set`))),
    SEC027: pods.flatMap(pod => containers(pod).filter(container => container?.securityContext?.allowPrivilegeEscalation !== false).map(container => finding(pod, `Container ${container.name} allows privilege escalation or does not disable it`))),
    SEC028: pods.filter(pod => json(pod)?.spec?.hostUsers === true).map(pod => finding(pod, 'hostUsers enabled')),
  };
}

function workloadResourceFindings(resources: ResourceStates, mode: 'requests' | 'limits', memoryOnly = false): Finding[] {
  const required: ('cpu' | 'memory')[] = memoryOnly ? ['memory'] : ['cpu', 'memory'];
  return allWorkloads(resources).flatMap(workload =>
    workloadContainers(workload).flatMap(container =>
      required
        .filter(resource => !hasResource(container, mode, resource))
        .map(resource => finding(workload, `Container ${container.name} missing ${resource} ${mode}`))
    )
  );
}

function workloadProbeFindings(resources: ResourceStates): Finding[] {
  return allWorkloads(resources).flatMap(workload =>
    workloadContainers(workload)
      .filter(container => !hasProbe(container))
      .map(container => finding(workload, `Container ${container.name} missing readiness or liveness probe`))
  );
}

function namespaceHasAny(resources: ResourceStates, namespaceName: string): boolean {
  return ['pod', 'secret', 'persistentvolumeclaim', 'service', 'configmap', 'deployment', 'statefulset', 'daemonset'].some(kind =>
    resources[kind].data.some(item => namespace(item) === namespaceName)
  );
}

function usedConfigMapKeys(resources: ResourceStates): Set<string> {
  const used = new Set<string>();
  resources.pod.data.forEach(pod => {
    const ns = namespace(pod) || 'default';
    (json(pod)?.spec?.volumes || []).forEach((volume: any) => volume.configMap?.name && used.add(`${ns}/${volume.configMap.name}`));
    containers(pod).forEach(container => {
      (container.env || []).forEach((env: any) => env?.valueFrom?.configMapKeyRef?.name && used.add(`${ns}/${env.valueFrom.configMapKeyRef.name}`));
      (container.envFrom || []).forEach((env: any) => env?.configMapRef?.name && used.add(`${ns}/${env.configMapRef.name}`));
    });
  });
  return used;
}

function usedSecretKeys(resources: ResourceStates): Set<string> {
  const used = new Set<string>();
  resources.pod.data.forEach(pod => {
    const ns = namespace(pod) || 'default';
    (json(pod)?.spec?.imagePullSecrets || []).forEach((secret: any) => secret.name && used.add(`${ns}/${secret.name}`));
    (json(pod)?.spec?.volumes || []).forEach((volume: any) => volume.secret?.secretName && used.add(`${ns}/${volume.secret.secretName}`));
    containers(pod).forEach(container => {
      (container.env || []).forEach((env: any) => env?.valueFrom?.secretKeyRef?.name && used.add(`${ns}/${env.valueFrom.secretKeyRef.name}`));
      (container.envFrom || []).forEach((env: any) => env?.secretRef?.name && used.add(`${ns}/${env.secretRef.name}`));
    });
  });
  resources.serviceaccount.data.forEach(sa => {
    const ns = namespace(sa) || 'default';
    [...(json(sa)?.secrets || []), ...(json(sa)?.imagePullSecrets || [])].forEach((secret: any) => secret.name && used.add(`${ns}/${secret.name}`));
  });
  return used;
}

function rbacResourceKey(resource: any): string {
  return `${namespace(resource) || ''}/${name(resource)}`;
}

function ruleContains(rule: any, field: string, expected: string): boolean {
  return (rule?.[field] || []).includes(expected);
}

function roleIsWildcard(role: any): boolean {
  return (json(role)?.rules || []).some(
    (rule: any) => ruleContains(rule, 'verbs', '*') && ruleContains(rule, 'resources', '*') && ruleContains(rule, 'apiGroups', '*')
  );
}

function roleIsSensitive(role: any): boolean {
  const sensitive = new Set(['secrets', 'pods/exec', 'roles', 'clusterroles', 'bindings', 'clusterrolebindings']);
  const dangerous = new Set(['*', 'create', 'update', 'delete']);

  return (json(role)?.rules || []).some((rule: any) => {
    const resources = rule?.resources || [];
    const verbs = rule?.verbs || [];

    return resources.some((resource: string) => sensitive.has(resource)) && verbs.some((verb: string) => dangerous.has(verb));
  });
}

function isBuiltInClusterRole(role: any): boolean {
  const roleName = name(role);
  const labels = objectLabels(role);
  const aksManagedClusterRoles = new Set([
    'aks-secretproviderclasses-admin-role',
    'aks-secretproviderclasses-viewer-role',
    'aks-service',
    'aks:trustedaccessrole:defender-cloudposture:microsoft-defender-operator',
  ]);

  if (['cluster-admin', 'admin', 'edit', 'view', 'system:public-info-viewer'].includes(roleName)) {
    return true;
  }

  return (
    roleName.startsWith('system:') ||
    roleName.startsWith('system:kube-') ||
    roleName.startsWith('system:node') ||
    aksManagedClusterRoles.has(roleName) ||
    labels['kubernetes.io/bootstrapping'] === 'rbac-defaults'
  );
}

function isDefaultKubernetesRBACBinding(binding: any): boolean {
  const bindingName = name(binding);
  const aksManagedBindings = new Set([
    'aks-cluster-admin-binding',
    'aks-cluster-admin-binding-aad',
    'aks-secretprovidersyncing-rolebinding',
    'aks-service-rolebinding',
  ]);

  return (
    bindingName.startsWith('system:') ||
    aksManagedBindings.has(bindingName) ||
    objectLabels(binding)['kubernetes.io/bootstrapping'] === 'rbac-defaults'
  );
}

function namespaceFromServiceAccountUsername(subjectName: string): string {
  const prefix = 'system:serviceaccount:';
  if (!subjectName.startsWith(prefix)) {
    return '';
  }

  return subjectName.slice(prefix.length).split(':')[0] || '';
}

function isKubernetesSystemSubjectName(subjectName: string): boolean {
  return (
    subjectName === 'system:masters' ||
    subjectName === 'system:nodes' ||
    subjectName.startsWith('system:node:') ||
    subjectName.startsWith('system:kube-') ||
    subjectName.startsWith('system:serviceaccount:kube-system:')
  );
}

function isExcludedRBACNamespace(namespaceName: string, config: KubeBuddyConfig): boolean {
  return namespaceSet(config.excludedNamespaces).has(namespaceName.trim().toLowerCase());
}

function isReportableRBACSubject(subject: any, defaultNamespace: string, config: KubeBuddyConfig): boolean {
  const subjectKind = String(subject?.kind || '').trim();
  const subjectName = String(subject?.name || '').trim();

  if (subjectKind === 'ServiceAccount') {
    const subjectNamespace = String(subject?.namespace || defaultNamespace || '').trim();
    return !isExcludedRBACNamespace(subjectNamespace, config);
  }

  if (subjectKind === 'User') {
    const serviceAccountNamespace = namespaceFromServiceAccountUsername(subjectName);
    if (serviceAccountNamespace && isExcludedRBACNamespace(serviceAccountNamespace, config)) {
      return false;
    }

    return !isKubernetesSystemSubjectName(subjectName);
  }

  if (subjectKind === 'Group') {
    return !isKubernetesSystemSubjectName(subjectName);
  }

  return true;
}

function bindingHasReportableRBACSubject(binding: any, defaultNamespace: string, config: KubeBuddyConfig): boolean {
  const subjects = json(binding)?.subjects || [];

  return subjects.length === 0 || subjects.some((subject: any) => isReportableRBACSubject(subject, defaultNamespace, config));
}

function overexposureMessage(roleName: string, wildcard: boolean, sensitive: boolean): string {
  if (roleName === 'cluster-admin') {
    return 'cluster-admin binding';
  }

  if (wildcard) {
    return 'Wildcard permission role';
  }

  if (sensitive) {
    return 'Access to sensitive resources';
  }

  return 'RBAC overexposure';
}

function rbacMisconfigFindings(resources: ResourceStates, config: KubeBuddyConfig): Finding[] {
  const namespaces = new Set(resources.namespace.data.map(ns => name(ns)));
  const roles = new Set(resources.role.data.map(role => rbacResourceKey(role)));
  const clusterRoles = new Set(resources.clusterrole.data.map(role => name(role)));
  const serviceAccounts = new Set(resources.serviceaccount.data.map(sa => rbacResourceKey(sa)));
  const findings: Finding[] = [];

  resources.rolebinding.data.forEach(binding => {
    const bindingNamespace = namespace(binding) || 'default';
    const roleRef = json(binding)?.roleRef;
    const roleName = roleRef?.name || '';

    if (!roleRef) {
      findings.push(finding(binding, 'Missing roleRef in RoleBinding'));
      return;
    }

    if (roleRef.kind === 'Role' && !roles.has(`${bindingNamespace}/${roleName}`)) {
      findings.push(finding(binding, `Missing Role: ${roleName}`));
    }

    if (roleRef.kind === 'ClusterRole' && !clusterRoles.has(roleName)) {
      findings.push(finding(binding, `Missing ClusterRole: ${roleName}`));
    }

    (json(binding)?.subjects || []).forEach((subject: any) => {
      if (subject?.kind !== 'ServiceAccount') {
        return;
      }

      const subjectNamespace = subject.namespace || bindingNamespace;
      if (isExcludedRBACNamespace(subjectNamespace, config)) {
        return;
      }

      if (!namespaces.has(subjectNamespace)) {
        findings.push(finding(binding, `ServiceAccount namespace does not exist: ${subjectNamespace}`));
      } else if (!serviceAccounts.has(`${subjectNamespace}/${subject.name}`)) {
        findings.push(finding(binding, `ServiceAccount not found: ${subjectNamespace}/${subject.name}`));
      }
    });
  });

  resources.clusterrolebinding.data.forEach(binding => {
    const roleRef = json(binding)?.roleRef;
    const roleName = roleRef?.name || '';

    if (!roleRef) {
      findings.push(finding(binding, 'Missing roleRef in ClusterRoleBinding'));
      return;
    }

    if (roleName && !clusterRoles.has(roleName)) {
      findings.push(finding(binding, `Missing ClusterRole: ${roleName}`));
    }

    (json(binding)?.subjects || []).forEach((subject: any) => {
      if (subject?.kind !== 'ServiceAccount') {
        return;
      }

      if (!subject.namespace) {
        findings.push(finding(binding, `Missing namespace for ServiceAccount subject: ${subject.name}`));
        return;
      }

      if (isExcludedRBACNamespace(subject.namespace, config)) {
        return;
      }

      if (!namespaces.has(subject.namespace)) {
        findings.push(finding(binding, `ServiceAccount namespace does not exist: ${subject.namespace}`));
      } else if (!serviceAccounts.has(`${subject.namespace}/${subject.name}`)) {
        findings.push(finding(binding, `ServiceAccount not found: ${subject.namespace}/${subject.name}`));
      }
    });
  });

  return findings;
}

function rbacOverexposureFindings(resources: ResourceStates, config: KubeBuddyConfig): Finding[] {
  const wildcardClusterRoles = new Set<string>();
  const sensitiveClusterRoles = new Set<string>();
  const wildcardRoles = new Set<string>();
  const sensitiveRoles = new Set<string>();

  resources.clusterrole.data.forEach(role => {
    if (roleIsWildcard(role)) {
      wildcardClusterRoles.add(name(role));
    }
    if (roleIsSensitive(role)) {
      sensitiveClusterRoles.add(name(role));
    }
  });

  resources.role.data.forEach(role => {
    const key = rbacResourceKey(role);
    if (roleIsWildcard(role)) {
      wildcardRoles.add(key);
    }
    if (roleIsSensitive(role)) {
      sensitiveRoles.add(key);
    }
  });

  return [
    ...resources.clusterrolebinding.data.flatMap(binding => {
      if (isDefaultKubernetesRBACBinding(binding)) {
        return [];
      }

      const roleName = json(binding)?.roleRef?.name || '';
      const isRisky =
        roleName === 'cluster-admin' || wildcardClusterRoles.has(roleName) || sensitiveClusterRoles.has(roleName);

      if (!isRisky) {
        return [];
      }

      return (json(binding)?.subjects || [])
        .filter((subject: any) => isReportableRBACSubject(subject, '', config))
        .map((subject: any) =>
          finding(
            binding,
            `${overexposureMessage(roleName, wildcardClusterRoles.has(roleName), sensitiveClusterRoles.has(roleName))}: ${subject.kind}/${subject.name}`
          )
        );
    }),
    ...resources.rolebinding.data.flatMap(binding => {
      const bindingNamespace = namespace(binding) || 'default';
      const roleName = json(binding)?.roleRef?.name || '';
      const roleKey = `${bindingNamespace}/${roleName}`;
      const clusterRoleRisk =
        json(binding)?.roleRef?.kind === 'ClusterRole' &&
        (roleName === 'cluster-admin' || wildcardClusterRoles.has(roleName) || sensitiveClusterRoles.has(roleName));
      const roleRisk = wildcardRoles.has(roleKey) || sensitiveRoles.has(roleKey);

      if (!clusterRoleRisk && !roleRisk) {
        return [];
      }

      return (json(binding)?.subjects || [])
        .filter((subject: any) => isReportableRBACSubject(subject, bindingNamespace, config))
        .map((subject: any) =>
          finding(
            binding,
            `${overexposureMessage(
              roleName,
              wildcardClusterRoles.has(roleName) || wildcardRoles.has(roleKey),
              sensitiveClusterRoles.has(roleName) || sensitiveRoles.has(roleKey)
            )}: ${subject.kind}/${subject.name}`
          )
        );
    }),
  ];
}

function usedServiceAccountKeys(resources: ResourceStates): Set<string> {
  const used = new Set<string>();

  resources.pod.data.forEach(pod => {
    used.add(`${namespace(pod) || 'default'}/${serviceAccountName(pod)}`);
  });

  [...resources.rolebinding.data, ...resources.clusterrolebinding.data].forEach(binding => {
    (json(binding)?.subjects || []).forEach((subject: any) => {
      if (subject?.kind === 'ServiceAccount') {
        used.add(`${subject.namespace || namespace(binding) || 'default'}/${subject.name}`);
      }
    });
  });

  return used;
}

function orphanedRolesFindings(resources: ResourceStates): Finding[] {
  const usedRoles = new Set<string>();
  const findings: Finding[] = [];

  resources.rolebinding.data.forEach(binding => {
    const roleRef = json(binding)?.roleRef || {};
    if (roleRef.kind === 'Role') {
      usedRoles.add(`${namespace(binding) || 'default'}/${roleRef.name}`);
    } else if (roleRef.kind === 'ClusterRole') {
      usedRoles.add(roleRef.name);
    }

    if ((json(binding)?.subjects || []).length === 0) {
      findings.push(finding(binding, 'RoleBinding has no subjects'));
    }
  });

  resources.clusterrolebinding.data.forEach(binding => {
    const roleName = json(binding)?.roleRef?.name;
    if (roleName) {
      usedRoles.add(roleName);
    }

    if (!isDefaultKubernetesRBACBinding(binding) && (json(binding)?.subjects || []).length === 0) {
      findings.push(finding(binding, 'ClusterRoleBinding has no subjects'));
    }
  });

  resources.role.data.forEach(role => {
    const key = rbacResourceKey(role);
    if (!usedRoles.has(key)) {
      findings.push(finding(role, (json(role)?.rules || []).length === 0 ? 'Role defines no rules' : 'Role is not referenced by bindings'));
    }
  });

  resources.clusterrole.data.forEach(role => {
    const roleName = name(role);
    if (isBuiltInClusterRole(role)) {
      if ((json(role)?.rules || []).length === 0) {
        findings.push(finding(role, 'ClusterRole has no rules'));
      }
      return;
    }

    if (!usedRoles.has(roleName)) {
      findings.push(finding(role, (json(role)?.rules || []).length === 0 ? 'ClusterRole defines no rules' : 'Unused ClusterRole'));
    }
  });

  return findings;
}

function boundRoleRefs(resources: ResourceStates, config: KubeBuddyConfig): Set<string> {
  const out = new Set<string>();

  resources.rolebinding.data.forEach(binding => {
    if (!bindingHasReportableRBACSubject(binding, namespace(binding) || 'default', config)) {
      return;
    }

    const roleRef = json(binding)?.roleRef || {};
    if (!roleRef.name) {
      return;
    }

    out.add(roleRef.kind === 'ClusterRole' ? `ClusterRole:${roleRef.name}` : `Role:${namespace(binding) || 'default'}/${roleRef.name}`);
  });

  resources.clusterrolebinding.data.forEach(binding => {
    if (isDefaultKubernetesRBACBinding(binding) || !bindingHasReportableRBACSubject(binding, '', config)) {
      return;
    }

    const roleName = json(binding)?.roleRef?.name;
    if (roleName) {
      out.add(`ClusterRole:${roleName}`);
    }
  });

  return out;
}

function grantsKubeletProxy(role: any): boolean {
  return (json(role)?.rules || []).some((rule: any) => (rule?.resources || []).includes('nodes/proxy') && (rule?.verbs || []).length > 0);
}

const nativeHandlers: Record<string, NativeHandler> = {
  ...Object.fromEntries(
    Object.keys(podSecurityHandlers({ pod: EMPTY_RESOURCE_STATE })).map(key => [
      key,
      (resources: ResourceStates) => podSecurityHandlers(resources)[key],
    ])
  ),
  CFG001: resources => {
    const used = usedConfigMapKeys(resources);
    return resources.configmap.data
      .filter(cm => !['kube-root-ca.crt', 'istio-ca-root'].includes(name(cm)) && !name(cm).startsWith('sh.helm.release.v1.'))
      .filter(cm => !used.has(`${namespace(cm)}/${name(cm)}`))
      .map(cm => finding(cm, 'ConfigMap appears unused'));
  },
  CFG002: resources => {
    const byName = new Map<string, string[]>();
    resources.configmap.data.forEach(cm => {
      if (['kube-root-ca.crt', 'istio-ca-root'].includes(name(cm))) return;
      byName.set(name(cm), [...(byName.get(name(cm)) || []), namespace(cm) || 'default']);
    });
    return [...byName.entries()].filter(([, namespaces]) => namespaces.length > 1).map(([cmName, namespaces]) => ({ resource: `configmap/${cmName}`, details: `Duplicated in ${namespaces.join(', ')}` }));
  },
  CFG003: resources => resources.configmap.data.filter(cm => JSON.stringify(json(cm)?.data || {}).length > 1048576).map(cm => finding(cm, 'ConfigMap exceeds 1 MiB')),
  EVENT001: resources => resources.events.data.filter(event => json(event)?.type === 'Warning').map(event => finding(event, json(event)?.message || 'Warning event')),
  EVENT002: resources => resources.events.data.filter(event => json(event)?.type === 'Warning').map(event => finding(event, json(event)?.reason || 'Warning event')),
  SEC014: (resources, config) => resources.pod.data.flatMap(pod =>
    containers(pod, false)
      .filter(container => !config.trustedRegistries.some(registry => canonicalContainerImageReference(String(container.image || '')).startsWith(registry)))
      .map(container => finding(pod, `Image from untrusted registry: ${container.image}`))
  ),
  JOB001: (resources, config) => resources.job.data.filter(job => daysSince(json(job)?.status?.startTime) !== null && (Date.now() - new Date(json(job)?.status?.startTime).getTime()) > config.thresholds.stuckJobHours * 60 * 60 * 1000 && !json(job)?.status?.succeeded).map(job => finding(job, `Job running longer than ${config.thresholds.stuckJobHours} hours`)),
  JOB002: resources => resources.job.data.filter(job => (json(job)?.status?.failed || 0) > 0 && !json(job)?.status?.succeeded).map(job => finding(job, `${json(job)?.status?.failed} failures`)),
  NET001: resources => resources.service.data.filter(service => json(service)?.spec?.type !== 'ExternalName' && !resources.endpoints.data.some(ep => namespace(ep) === namespace(service) && name(ep) === name(service) && (json(ep)?.subsets || []).length > 0) && !resources.endpointslice.data.some(ep => namespace(ep) === namespace(service) && json(ep)?.metadata?.labels?.['kubernetes.io/service-name'] === name(service))).map(service => finding(service, 'No endpoints or endpoint slices')),
  NET002: resources => resources.service.data.filter(service => ['LoadBalancer', 'NodePort'].includes(json(service)?.spec?.type)).map(service => finding(service, json(service)?.spec?.type)),
  NET003: resources => resources.ingress.data.flatMap(ingress => {
    const findings: Finding[] = [];
    if (!json(ingress)?.spec?.ingressClassName && !objectAnnotations(ingress)['kubernetes.io/ingress.class']) findings.push(finding(ingress, 'Missing ingress class'));
    (json(ingress)?.spec?.tls || []).forEach((tls: any) => {
      if (tls.secretName && !resources.secret.data.some(secret => namespace(secret) === namespace(ingress) && name(secret) === tls.secretName)) findings.push(finding(ingress, `TLS secret ${tls.secretName} not found`));
    });
    return findings;
  }),
  NET004: resources => resources.namespace.data.filter(ns => resources.pod.data.some(pod => namespace(pod) === name(ns)) && !resources.networkpolicy.data.some(policy => namespace(policy) === name(ns))).map(ns => finding(ns, 'Namespace has pods but no NetworkPolicy')),
  NET005: resources => resources.ingress.data.flatMap(ingress => {
    const seen = new Set<string>();
    return (json(ingress)?.spec?.rules || []).flatMap((rule: any) => (rule.http?.paths || []).flatMap((path: any) => {
      const key = `${rule.host || '*'}${path.path || '/'}`;
      if (seen.has(key)) return [finding(ingress, `Duplicate host/path ${key}`)];
      seen.add(key);
      return [];
    }));
  }),
  NET006: resources => resources.ingress.data.flatMap(ingress => (json(ingress)?.spec?.rules || []).filter((rule: any) => String(rule.host || '').includes('*')).map((rule: any) => finding(ingress, `Wildcard host ${rule.host}`))),
  NET007: resources => resources.service.data.filter(service => json(service)?.spec?.type !== 'ExternalName' && serviceSelector(service) && resources.pod.data.some(pod => namespace(pod) === namespace(service) && selectorMatches(serviceSelector(service), objectLabels(pod)) && json(pod)?.status?.phase === 'Running')).filter(service => !(json(service)?.spec?.ports || []).some((port: any) => Number(port.targetPort || port.port) > 0)).map(service => finding(service, 'Service has matching pods but questionable target ports')),
  NET008: resources => resources.service.data.filter(service => json(service)?.spec?.type === 'ExternalName' && /^\d+\.\d+\.\d+\.\d+$/.test(json(service)?.spec?.externalName || '')).map(service => finding(service, `ExternalName points to IP ${json(service)?.spec?.externalName}`)),
  NET009: resources => resources.networkpolicy.data.filter(policy => (json(policy)?.spec?.ingress || []).length === 0 || (json(policy)?.spec?.egress || []).length === 0).map(policy => finding(policy, 'Permissive empty ingress or egress rules')),
  NET010: resources => resources.networkpolicy.data.filter(policy => JSON.stringify(json(policy)?.spec || {}).includes('0.0.0.0/0')).map(policy => finding(policy, 'Allows 0.0.0.0/0')),
  NET011: resources => resources.networkpolicy.data.filter(policy => !(json(policy)?.spec?.policyTypes || []).length).map(policy => finding(policy, 'policyTypes missing')),
  NET012: resources => resources.pod.data.filter(pod => json(pod)?.spec?.hostNetwork).map(pod => finding(pod, 'hostNetwork enabled')),
  NET013: resources => resources.ingress.data.length > 0 && resources.gateway.data.length === 0 && resources.httproute.data.length === 0 ? [{ resource: 'gateway-api/adoption', details: 'Ingress is in use but Gateway API resources are not adopted' }] : [],
  NET014: resources => resources.httproute.data.filter(route => !(json(route)?.status?.parents || []).some((parent: any) => (parent.conditions || []).some((condition: any) => condition.type === 'Accepted' && String(condition.status).toLowerCase() === 'true'))).map(route => finding(route, 'HTTPRoute is not accepted')),
  NET015: resources => resources.gateway.data.filter(gateway => !resources.httproute.data.some(route => (json(route)?.spec?.parentRefs || []).some((parent: any) => (parent.namespace || namespace(route)) === namespace(gateway) && parent.name === name(gateway)))).map(gateway => finding(gateway, 'Gateway has no attached HTTPRoutes')),
  NET016: resources => resources.gateway.data.flatMap(gateway => (json(gateway)?.status?.conditions || []).filter((condition: any) => ['Accepted', 'Programmed'].includes(condition.type) && String(condition.status).toLowerCase() !== 'true').map((condition: any) => finding(gateway, `${condition.type}: ${condition.reason || condition.message || 'not healthy'}`))),
  NET017: resources => resources.gateway.data.flatMap(gateway => (json(gateway)?.spec?.listeners || []).flatMap((listener: any) => (listener.tls?.certificateRefs || []).filter((ref: any) => ref.kind === 'Secret' || !ref.kind).filter((ref: any) => !resources.secret.data.some(secret => namespace(secret) === (ref.namespace || namespace(gateway)) && name(secret) === ref.name)).map((ref: any) => finding(gateway, `Missing TLS secret ${ref.name}`)))),
  NET018: resources => {
    const grouped = new Map<string, any[]>();
    resources.service.data.forEach(service => {
      const key = `${namespace(service)}|${selectorKey(serviceSelector(service))}`;
      if (key.endsWith('|')) return;
      grouped.set(key, [...(grouped.get(key) || []), service]);
    });
    return [...grouped.values()].filter(group => group.length > 1).flatMap(group => group.map(service => finding(service, `Duplicate selector also used by ${group.map(name).join(', ')}`)));
  },
  NET020: resources => [...resources.deployment.data, ...resources.daemonset.data, ...resources.statefulset.data, ...resources.pod.data, ...resources.service.data].filter(item => /ingress-nginx/i.test(JSON.stringify(json(item)))).map(item => finding(item, 'Ingress NGINX detected')),
  NODE001: resources => resources.node.data.filter(item => !nodeReady(item)).map(item => finding(item, 'Ready condition is not True')),
  NODE002: emptyHandler,
  NODE003: (resources, config) => resources.node.data.filter(node => Number(json(node)?.status?.capacity?.pods || 0) > 0 && resources.pod.data.filter(pod => json(pod)?.spec?.nodeName === name(node)).length / Number(json(node)?.status?.capacity?.pods || 1) > config.thresholds.podsPerNodeCritical / 100).map(node => finding(node, `Pod capacity above ${config.thresholds.podsPerNodeCritical}%`)),
  NS001: resources => resources.namespace.data.filter(ns => !namespaceHasAny(resources, name(ns))).map(ns => finding(ns, 'Namespace appears unused')),
  NS002: resources => resources.namespace.data.filter(ns => !resources.resourcequota.data.some(quota => namespace(quota) === name(ns))).map(ns => finding(ns, 'No ResourceQuota')),
  NS003: resources => resources.namespace.data.filter(ns => !resources.limitrange.data.some(limit => namespace(limit) === name(ns))).map(ns => finding(ns, 'No LimitRange')),
  NS004: resources => resources.pod.data.filter(pod => namespace(pod) === 'default').map(pod => finding(pod, 'Pod running in default namespace')),
  POD001: (resources, config) => resources.pod.data.map(pod => ({ pod, restarts: restartCount(pod) })).filter(item => item.restarts > config.thresholds.restartsWarning).map(item => finding(item.pod, `${item.restarts} restarts`)),
  POD002: (resources, config) => resources.pod.data.map(pod => ({ pod, age: daysSince(json(pod)?.status?.startTime) })).filter(item => json(item.pod)?.status?.phase === 'Running' && item.age !== null && item.age > config.thresholds.podAgeWarning).map(item => finding(item.pod, `${item.age} days old`)),
  POD006: resources => resources.pod.data.filter(pod => /debugger/i.test(name(pod))).map(pod => finding(pod, json(pod)?.status?.phase || 'Debug pod left behind')),
  POD007: resources => resources.pod.data.filter(pod => podImages(pod).some(image => !image.includes('@sha256:') && (image.endsWith(':latest') || image.lastIndexOf(':') <= image.lastIndexOf('/')))).map(pod => finding(pod, podImages(pod).join(', '))),
  POD008: resources => resources.pod.data.filter(pod => json(pod)?.spec?.automountServiceAccountToken !== false).map(pod => finding(pod, 'automountServiceAccountToken is enabled or inherited')),
  POD009: resources => resources.pod.data.filter(pod => JSON.stringify(json(pod)?.status || {}).match(/Unhealthy|Unknown/)).map(pod => finding(pod, 'Allocated device resource reports Unhealthy or Unknown')),
  PV001: resources => resources.persistentvolume.data.filter(pv => json(pv)?.status?.phase !== 'Bound' && !resources.persistentvolumeclaim.data.some(pvc => json(pvc)?.spec?.volumeName === name(pv))).map(pv => finding(pv, 'PV is not bound to any PVC')),
  PVC001: resources => resources.persistentvolumeclaim.data.filter(pvc => !resources.pod.data.some(pod => namespace(pod) === namespace(pvc) && (json(pod)?.spec?.volumes || []).some((volume: any) => volume.persistentVolumeClaim?.claimName === name(pvc)))).map(pvc => finding(pvc, 'PVC not used by any pod')),
  PVC003: resources => resources.persistentvolumeclaim.data.filter(pvc => (json(pvc)?.spec?.accessModes || []).includes('ReadWriteMany')).filter(pvc => !json(pvc)?.spec?.storageClassName || resources.storageclass.data.some(sc => name(sc) === json(pvc)?.spec?.storageClassName && /disk|ebs|pd|cinder|local-path/i.test(json(sc)?.provisioner || ''))).map(pvc => finding(pvc, 'ReadWriteMany PVC may use block storage')),
  PVC004: resources => resources.persistentvolumeclaim.data.filter(pvc => json(pvc)?.status?.phase === 'Pending').map(pvc => finding(pvc, 'Pending')),
  PVC005: resources => resources.persistentvolumeclaim.data.filter(pvc => JSON.stringify(json(pvc)?.status || {}).toLowerCase().includes('fail')).map(pvc => finding(pvc, 'PVC resize or allocation failure signal')),
  RBAC001: rbacMisconfigFindings,
  RBAC002: rbacOverexposureFindings,
  RBAC003: resources => {
    const used = usedServiceAccountKeys(resources);
    return resources.serviceaccount.data
      .filter(sa => !used.has(rbacResourceKey(sa)))
      .map(sa => finding(sa, 'ServiceAccount not used by pods or RBAC bindings'));
  },
  RBAC004: orphanedRolesFindings,
  RBAC005: (resources, config) => {
    const bound = boundRoleRefs(resources, config);
    return [
      ...resources.clusterrole.data
        .filter(role => !isBuiltInClusterRole(role) && bound.has(`ClusterRole:${name(role)}`) && grantsKubeletProxy(role))
        .map(role => finding(role, 'Grants nodes/proxy access')),
      ...resources.role.data
        .filter(role => bound.has(`Role:${rbacResourceKey(role)}`) && grantsKubeletProxy(role))
        .map(role => finding(role, 'Grants nodes/proxy access')),
    ];
  },
  SC002_AKS: resources => resources.storageclass.data.filter(sc => ['kubernetes.io/azure-disk', 'kubernetes.io/azure-file'].includes(json(sc)?.provisioner)).map(sc => finding(sc, 'Azure in-tree provisioner')),
  SC002_EXPANSION: resources => resources.storageclass.data.filter(sc => json(sc)?.allowVolumeExpansion !== true).map(sc => finding(sc, 'Volume expansion disabled')),
  SC003: emptyHandler,
  SEC001: resources => {
    const used = usedSecretKeys(resources);
    return resources.secret.data
      .filter(secret => !name(secret).startsWith('sh.helm.release.v1.') && !name(secret).startsWith('bootstrap-token-') && !name(secret).startsWith('default-token-') && name(secret) !== 'kube-root-ca.crt')
      .filter(secret => !used.has(`${namespace(secret)}/${name(secret)}`))
      .map(secret => finding(secret, 'Secret appears unused'));
  },
  SEC007: resources => resources.namespace.data.filter(ns => !objectLabels(ns)?.['pod-security.kubernetes.io/enforce']).map(ns => finding(ns, 'No pod-security enforce label')),
  SEC025: resources => resources.validatingadmissionpolicy.data.filter(policy => JSON.stringify(json(policy)?.spec || {}).toLowerCase().includes('latest')).map(policy => finding(policy, 'Admission policy references latest tag controls')),
  WRK001: resources => resources.daemonset.data.filter(daemonSet => (json(daemonSet)?.status?.numberReady || 0) < (json(daemonSet)?.status?.desiredNumberScheduled || 0)).map(daemonSet => finding(daemonSet, `${json(daemonSet)?.status?.numberReady || 0}/${json(daemonSet)?.status?.desiredNumberScheduled || 0} ready`)),
  WRK002: resources => resources.deployment.data.filter(deployment => (json(deployment)?.status?.availableReplicas || 0) < (json(deployment)?.spec?.replicas || 1)).map(deployment => finding(deployment, `${json(deployment)?.status?.availableReplicas || 0}/${json(deployment)?.spec?.replicas || 1} available`)),
  WRK003: resources => resources.statefulset.data.filter(statefulSet => (json(statefulSet)?.status?.readyReplicas || 0) < (json(statefulSet)?.status?.replicas || 1)).map(statefulSet => finding(statefulSet, `${json(statefulSet)?.status?.readyReplicas || 0}/${json(statefulSet)?.status?.replicas || 1} ready`)),
  WRK004: resources => resources.horizontalpodautoscaler.data.filter(hpa => !(json(hpa)?.status?.currentMetrics || []).length || (json(hpa)?.status?.conditions || []).some((condition: any) => condition.status === 'False')).map(hpa => finding(hpa, 'HPA has no metrics or unhealthy condition')),
  WRK005: resources => workloadResourceFindings(resources, 'requests'),
  WRK006: resources => resources.poddisruptionbudget.data.filter(pdb => Number(json(pdb)?.status?.expectedPods || 0) === 0).map(pdb => finding(pdb, 'PDB matches 0 pods')),
  WRK007: workloadProbeFindings,
  WRK008: resources => resources.deployment.data.filter(deployment => !resources.pod.data.some(pod => namespace(pod) === namespace(deployment) && selectorMatches(workloadSelector(deployment), objectLabels(pod)))).map(deployment => finding(deployment, 'Deployment selector matches no pods')),
  WRK009: resources => resources.deployment.data.filter(deployment => !selectorMatches(workloadSelector(deployment), workloadLabels(deployment))).map(deployment => finding(deployment, 'Deployment selector does not match template labels')),
  WRK010: resources => resources.horizontalpodautoscaler.data.filter(hpa => (json(hpa)?.spec?.metrics || []).some((metric: any) => metric.type === 'Resource')).flatMap(hpa => {
    const targetName = json(hpa)?.spec?.scaleTargetRef?.name;
    const workload = allWorkloads(resources).find(item => namespace(item) === namespace(hpa) && name(item) === targetName);
    return workload ? workloadContainers(workload).filter(container => !hasResource(container, 'requests', 'cpu') && !hasResource(container, 'requests', 'memory')).map(container => finding(hpa, `Target container ${container.name} missing requests`)) : [finding(hpa, `Target ${targetName} not found`)];
  }),
  WRK011: resources => resources.verticalpodautoscaler.data.map(vpa => finding(vpa, 'VPA detected; verify update mode and workload requests')),
  WRK012: resources => allWorkloads(resources).filter(workload => Number(json(workload)?.spec?.replicas || 1) > 1 && !resources.poddisruptionbudget.data.some(pdb => namespace(pdb) === namespace(workload) && selectorMatches(json(pdb)?.spec?.selector?.matchLabels, workloadLabels(workload)))).map(workload => finding(workload, 'Replicated workload has no matching PDB')),
  WRK013: (resources, config) => resources.pod.data.filter(pod => JSON.stringify(json(pod)?.status || {}).match(/CrashLoopBackOff|OOMKilled/) || restartCount(pod) >= config.thresholds.restartsCritical).map(pod => finding(pod, 'CrashLoopBackOff, OOMKilled, or high restarts')),
  WRK014: resources => workloadResourceFindings(resources, 'limits', true),
  WRK015: resources => allWorkloads(resources).filter(workload => !(json(workload)?.spec?.template?.spec?.topologySpreadConstraints || []).length).map(workload => finding(workload, 'No topologySpreadConstraints')),
};

function evaluateCheck(check: GeneratedCheck, resources: ResourceStates, config: KubeBuddyConfig): CheckResult {
  if (check.nativeHandler) {
    const handler = nativeHandlers[check.nativeHandler];
    if (!handler) {
      return resultFromCheck(
        check,
        [],
        'skipped',
        `Native handler ${check.nativeHandler} is not implemented in the Headlamp plugin yet.`
      );
    }
    return resultFromCheck(check, handler(resources, config));
  }

  const items = getResourcesForCheck(check, resources);
  if (!items) {
    return resultFromCheck(check, [], 'skipped', `Resource kind ${check.resourceKind} is not mapped in the plugin yet.`);
  }

  const findings = items.flatMap(resource => {
    const value = resolveExpression(json(resource), check.value);
    return evaluateOperator(check.operator || 'exists', value, check.expected)
      ? [finding(resource, valueDetails(check, value))]
      : [];
  });

  return resultFromCheck(check, findings);
}

function useKubeBuddyChecks(
  enabled = true,
  initialChecks: CheckResult[] = EMPTY_CHECKS,
  config: KubeBuddyConfig = defaultKubeBuddyConfig()
): {
  checks: CheckResult[];
  loading: boolean;
  errors: string[];
  scanning: boolean;
  scanProgress: number;
  scanLogs: ScanLogEntry[];
} {
  const clusterRoles = useResourceList<any>(K8s.ResourceClasses.ClusterRole.useList());
  const clusterRoleBindings = useResourceList<any>(K8s.ResourceClasses.ClusterRoleBinding.useList());
  const configMaps = useResourceList<any>(K8s.ResourceClasses.ConfigMap.useList());
  const daemonSets = useResourceList<any>(K8s.ResourceClasses.DaemonSet.useList());
  const deployments = useResourceList<any>(K8s.ResourceClasses.Deployment.useList());
  const endpoints = useResourceList<any>(K8s.ResourceClasses.Endpoints.useList());
  const endpointSlices = useResourceList<any>(K8s.ResourceClasses.EndpointSlice.useList());
  const gateways = useResourceList<any>(K8s.ResourceClasses.Gateway.useList());
  const hpas = useResourceList<any>(K8s.ResourceClasses.HorizontalPodAutoscaler.useList());
  const httpRoutes = useResourceList<any>(K8s.ResourceClasses.HTTPRoute.useList());
  const ingresses = useResourceList<any>(K8s.ResourceClasses.Ingress.useList());
  const jobs = useResourceList<any>(K8s.ResourceClasses.Job.useList());
  const limitRanges = useResourceList<any>(K8s.ResourceClasses.LimitRange.useList());
  const namespaces = useResourceList<any>(K8s.ResourceClasses.Namespace.useList());
  const networkPolicies = useResourceList<any>(K8s.ResourceClasses.NetworkPolicy.useList());
  const nodes = useResourceList<any>(K8s.ResourceClasses.Node.useList());
  const pdbs = useResourceList<any>(K8s.ResourceClasses.PodDisruptionBudget.useList());
  const persistentVolumes = useResourceList<any>(K8s.ResourceClasses.PersistentVolume.useList());
  const pvcs = useResourceList<any>(K8s.ResourceClasses.PersistentVolumeClaim.useList());
  const pods = useResourceList<any>(K8s.ResourceClasses.Pod.useList());
  const resourceQuotas = useResourceList<any>(K8s.ResourceClasses.ResourceQuota.useList());
  const roles = useResourceList<any>(K8s.ResourceClasses.Role.useList());
  const roleBindings = useResourceList<any>(K8s.ResourceClasses.RoleBinding.useList());
  const secrets = useResourceList<any>(K8s.ResourceClasses.Secret.useList());
  const serviceAccounts = useResourceList<any>(K8s.ResourceClasses.ServiceAccount.useList());
  const services = useResourceList<any>(K8s.ResourceClasses.Service.useList());
  const statefulSets = useResourceList<any>(K8s.ResourceClasses.StatefulSet.useList());
  const storageClasses = useResourceList<any>(K8s.ResourceClasses.StorageClass.useList());
  const excludedNamespaceSet = React.useMemo(
    () => namespaceSet(config.excludedNamespaces),
    [config.excludedNamespaces.join('\n')]
  );
  const filteredClusterRoles = filterResourceState(clusterRoles, excludedNamespaceSet);
  const filteredClusterRoleBindings = filterResourceState(clusterRoleBindings, excludedNamespaceSet);
  const filteredConfigMaps = filterResourceState(configMaps, excludedNamespaceSet);
  const filteredDaemonSets = filterResourceState(daemonSets, excludedNamespaceSet);
  const filteredDeployments = filterResourceState(deployments, excludedNamespaceSet);
  const filteredEndpoints = filterResourceState(endpoints, excludedNamespaceSet);
  const filteredEndpointSlices = filterResourceState(endpointSlices, excludedNamespaceSet);
  const filteredGateways = filterResourceState(gateways, excludedNamespaceSet);
  const filteredHpas = filterResourceState(hpas, excludedNamespaceSet);
  const filteredHttpRoutes = filterResourceState(httpRoutes, excludedNamespaceSet);
  const filteredIngresses = filterResourceState(ingresses, excludedNamespaceSet);
  const filteredJobs = filterResourceState(jobs, excludedNamespaceSet);
  const filteredLimitRanges = filterResourceState(limitRanges, excludedNamespaceSet);
  const filteredNamespaces = filterResourceState(namespaces, excludedNamespaceSet);
  const filteredNetworkPolicies = filterResourceState(networkPolicies, excludedNamespaceSet);
  const filteredNodes = filterResourceState(nodes, excludedNamespaceSet);
  const filteredPersistentVolumes = filterResourceState(persistentVolumes, excludedNamespaceSet);
  const filteredPvcs = filterResourceState(pvcs, excludedNamespaceSet);
  const filteredPods = filterResourceState(pods, excludedNamespaceSet);
  const filteredPdbs = filterResourceState(pdbs, excludedNamespaceSet);
  const filteredResourceQuotas = filterResourceState(resourceQuotas, excludedNamespaceSet);
  const filteredRoles = filterResourceState(roles, excludedNamespaceSet);
  const filteredRoleBindings = filterResourceState(roleBindings, excludedNamespaceSet);
  const filteredSecrets = filterResourceState(secrets, excludedNamespaceSet);
  const filteredServiceAccounts = filterResourceState(serviceAccounts, excludedNamespaceSet);
  const filteredServices = filterResourceState(services, excludedNamespaceSet);
  const filteredStatefulSets = filterResourceState(statefulSets, excludedNamespaceSet);
  const filteredStorageClasses = filterResourceState(storageClasses, excludedNamespaceSet);

  const resources: ResourceStates = {
    clusterrole: filteredClusterRoles,
    clusterrolebinding: filteredClusterRoleBindings,
    configmap: filteredConfigMaps,
    daemonset: filteredDaemonSets,
    deployment: filteredDeployments,
    endpoint: filteredEndpoints,
    endpoints: filteredEndpoints,
    endpointslice: filteredEndpointSlices,
    events: EMPTY_RESOURCE_STATE,
    gateway: filteredGateways,
    horizontalpodautoscaler: filteredHpas,
    httproute: filteredHttpRoutes,
    ingress: filteredIngresses,
    jobs: filteredJobs,
    job: filteredJobs,
    limitrange: filteredLimitRanges,
    namespace: filteredNamespaces,
    networkpolicy: filteredNetworkPolicies,
    node: filteredNodes,
    persistentvolume: filteredPersistentVolumes,
    persistentvolumeclaim: filteredPvcs,
    pod: filteredPods,
    poddisruptionbudget: filteredPdbs,
    resourcequota: filteredResourceQuotas,
    role: filteredRoles,
    'role,clusterrole': { data: [...filteredRoles.data, ...filteredClusterRoles.data], loading: roles.loading || clusterRoles.loading },
    rolebinding: filteredRoleBindings,
    secret: filteredSecrets,
    service: filteredServices,
    serviceaccount: filteredServiceAccounts,
    statefulset: filteredStatefulSets,
    storageclass: filteredStorageClasses,
    validatingadmissionpolicy: EMPTY_RESOURCE_STATE,
    verticalpodautoscaler: EMPTY_RESOURCE_STATE,
  };

  const states: ResourceStateEntry[] = [
    { ...clusterRoles, label: 'ClusterRoles' },
    { ...clusterRoleBindings, label: 'ClusterRoleBindings' },
    { ...configMaps, label: 'ConfigMaps' },
    { ...daemonSets, label: 'DaemonSets' },
    { ...deployments, label: 'Deployments' },
    { ...endpoints, label: 'Endpoints' },
    { ...endpointSlices, label: 'EndpointSlices' },
    { ...gateways, label: 'Gateways' },
    { ...hpas, label: 'HorizontalPodAutoscalers' },
    { ...httpRoutes, label: 'HTTPRoutes' },
    { ...ingresses, label: 'Ingresses' },
    { ...jobs, label: 'Jobs' },
    { ...limitRanges, label: 'LimitRanges' },
    { ...namespaces, label: 'Namespaces' },
    { ...networkPolicies, label: 'NetworkPolicies' },
    { ...nodes, label: 'Nodes' },
    { ...pdbs, label: 'PodDisruptionBudgets' },
    { ...persistentVolumes, label: 'PersistentVolumes' },
    { ...pvcs, label: 'PersistentVolumeClaims' },
    { ...pods, label: 'Pods' },
    { ...resourceQuotas, label: 'ResourceQuotas' },
    { ...roles, label: 'Roles' },
    { ...roleBindings, label: 'RoleBindings' },
    { ...secrets, label: 'Secrets' },
    { ...serviceAccounts, label: 'ServiceAccounts' },
    { ...services, label: 'Services' },
    { ...statefulSets, label: 'StatefulSets' },
    { ...storageClasses, label: 'StorageClasses' },
  ];
  const loading = states.some(state => state.loading && !isOptionalMissingApi(state.label, state.error));
  const errors = Array.from(
    new Set(
      states
        .filter(state => state.error && !isOptionalMissingApi(state.label, state.error))
        .map(state => formatResourceError(state.label, state.error))
    )
  );
  const activeChecks = React.useMemo(() => {
    const excluded = new Set(config.excludedChecks.map(id => id.toUpperCase()));
    return KUBERNETES_CHECKS.filter(check => !excluded.has(check.id.toUpperCase()));
  }, [config.excludedChecks.join('\n')]);
  const [checks, setChecks] = React.useState<CheckResult[]>(initialChecks);
  const [scanning, setScanning] = React.useState(false);
  const [scanProgress, setScanProgress] = React.useState(0);
  const [scanLogs, setScanLogs] = React.useState<ScanLogEntry[]>([]);
  const scanStartedRef = React.useRef(false);

  React.useEffect(() => {
    if (!enabled) {
      scanStartedRef.current = false;
      setChecks(initialChecks);
      setScanning(false);
      setScanProgress(initialChecks.length ? 100 : 0);
      setScanLogs(initialChecks.length ? [scanLogEntry(`Loaded saved scan with ${initialChecks.length} checks.`)] : []);
      return undefined;
    }

    if (loading) {
      scanStartedRef.current = false;
      setChecks([]);
      setScanning(false);
      setScanProgress(0);
      setScanLogs([
        scanLogEntry('Waiting for Headlamp to load Kubernetes resources.'),
      ]);
      return undefined;
    }

    if (scanStartedRef.current) {
      return undefined;
    }

    scanStartedRef.current = true;

    let cancelled = false;
    let timer: number | undefined;
    let index = 0;
    const results: CheckResult[] = [];

    setChecks([]);
    setScanning(true);
    setScanProgress(0);
    setScanLogs([
      scanLogEntry(`Starting Kubernetes check scan with ${activeChecks.length} checks.`),
    ]);

    const appendLog = (
      message: string,
      level: ScanLogEntry['level'] = 'info',
      extra: Pick<ScanLogEntry, 'status' | 'findings'> = {}
    ) => {
      setScanLogs(previous => [
        ...previous.slice(-199),
        scanLogEntry(message, level, extra),
      ]);
    };

    const evaluateChunk = () => {
      const stopAt = Math.min(index + CHECKS_PER_SCAN_STEP, activeChecks.length);

      while (index < stopAt) {
        const check = activeChecks[index];
        appendLog(`Running ${check.id}: ${check.name}`);
        const result = evaluateCheck(check, resources, config);
        results.push(result);
        appendLog(resultLogMessage(result), resultLogLevel(result));
        index += 1;
      }

      if (cancelled) {
        return;
      }

      setChecks([...results]);
      setScanProgress(activeChecks.length === 0 ? 100 : Math.round((index / activeChecks.length) * 100));

      if (index < activeChecks.length) {
        timer = window.setTimeout(evaluateChunk, SCAN_STEP_DELAY_MS);
      } else {
        appendLog(`Scan complete. Evaluated ${results.length} checks.`, 'success');
        setScanning(false);
      }
    };

    timer = window.setTimeout(evaluateChunk, SCAN_STEP_DELAY_MS);

    return () => {
      cancelled = true;
      if (timer) {
        window.clearTimeout(timer);
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, initialChecks, loading]);

  return { checks, loading: enabled ? loading : false, errors: enabled ? errors : [], scanning, scanProgress, scanLogs };
}

function KubeBuddyScoreBadge() {
  const location = useLocation();
  const isClusterRoute = /^\/c\/[^/]+/.test(location.pathname);

  if (!isClusterRoute) {
    return null;
  }

  return <KubeBuddyScoreBadgeContent clusterKey={clusterKeyFromPath(location.pathname)} />;
}

function KubeBuddyScoreBadgeContent({ clusterKey }: { clusterKey: string }) {
  const [storedScore, setStoredScore] = React.useState<StoredScore | null>(() => readStoredScore(clusterKey));
  const [, setFreshnessTick] = React.useState(0);

  React.useEffect(() => {
    const updateStoredScore = () => setStoredScore(readStoredScore(clusterKey));

    updateStoredScore();
    window.addEventListener(SCORE_UPDATED_EVENT, updateStoredScore);
    window.addEventListener('storage', updateStoredScore);

    return () => {
      window.removeEventListener(SCORE_UPDATED_EVENT, updateStoredScore);
      window.removeEventListener('storage', updateStoredScore);
    };
  }, [clusterKey]);

  React.useEffect(() => {
    const timer = window.setInterval(() => setFreshnessTick(tick => tick + 1), 60000);

    return () => {
      window.clearInterval(timer);
    };
  }, []);

  if (!storedScore) {
    return null;
  }

  const fresh = isFreshScore(storedScore);

  return (
    <Tooltip
      title={`KubeBuddy score ${storedScore.value}%. ${storedScore.failed} failed checks out of ${storedScore.total}. Completed ${formatScoreAge(storedScore)}. ${
        fresh ? 'Fresh score.' : 'Stale score; run a new scan when you need current results.'
      }`}
    >
      <Chip
        component="a"
        href="/kubebuddy"
        icon={<KubeBuddyLogoMark />}
        label={`${storedScore.value}% ${fresh ? 'Fresh' : 'Stale'}`}
        size="small"
        sx={theme => ({
          bgcolor: scoreBadgeColor(storedScore.value, theme),
          borderRadius: 999,
          fontSize: '0.95rem',
          fontWeight: 800,
          height: 30,
          px: 0.75,
          '& .MuiChip-icon': {
            color: 'inherit',
            height: 19,
            ml: 0.7,
            mr: 0.15,
            width: 19,
          },
          '& .MuiChip-label': {
            lineHeight: 1,
            pl: 0.35,
            pr: 0.8,
          },
          color: scoreBadgeContrastColor(storedScore.value, theme),
          '&:hover': {
            bgcolor: scoreBadgeColor(storedScore.value, theme),
            filter: 'brightness(0.95)',
          },
        })}
      />
    </Tooltip>
  );
}

function ScoreHero({ checks }: { checks: CheckResult[] }) {
  const score = scoreChecks(checks);
  const high = checks.filter(check => check.status === 'failed' && check.severity === 'high').length;
  const warning = checks.filter(check => check.status === 'failed' && check.severity === 'warning').length;
  const scoreColorName = scoreColor(score.value);
  const metricCards = [
    { label: 'Passed', value: score.passed, color: 'success.main' },
    { label: 'Failed', value: score.failed, color: 'error.main' },
    { label: 'Skipped', value: score.skipped, color: 'warning.main' },
    { label: 'High', value: high, color: 'error.main' },
    { label: 'Warning', value: warning, color: 'warning.main' },
  ];

  return (
    <Paper variant="outlined" sx={{ p: 2.5 }}>
      <Stack direction={{ xs: 'column', lg: 'row' }} spacing={2.5} alignItems={{ xs: 'stretch', lg: 'center' }}>
        <Stack direction="row" spacing={2} alignItems="center" sx={{ minWidth: { lg: 260 } }}>
          <Box
            sx={theme => ({
              alignItems: 'center',
              background: `conic-gradient(${theme.palette[scoreColorName].main} ${score.value * 3.6}deg, ${theme.palette.action.disabledBackground} 0deg)`,
              borderRadius: '50%',
              display: 'flex',
              height: 112,
              justifyContent: 'center',
              position: 'relative',
              width: 112,
              '&::after': {
                bgcolor: theme.palette.background.paper,
                borderRadius: '50%',
                content: '""',
                height: 78,
                position: 'absolute',
                width: 78,
              },
            })}
          >
            <Box sx={{ position: 'relative', textAlign: 'center', zIndex: 1 }}>
              <Typography variant="h4" sx={{ fontWeight: 800, lineHeight: 1 }}>
                {score.value}
              </Typography>
              <Typography variant="caption" color="text.secondary">
                /100
              </Typography>
            </Box>
          </Box>
          <Box>
            <Typography variant="overline">Cluster Score</Typography>
            <Typography variant="body2" color="text.secondary">
              Weighted health score from {score.total} evaluated checks.
            </Typography>
          </Box>
        </Stack>
        <Stack
          direction={{ xs: 'column', sm: 'row' }}
          spacing={1.5}
          sx={{ flex: 1 }}
        >
          {metricCards.map(card => (
            <Paper
              key={card.label}
              variant="outlined"
              sx={theme => ({
                flex: 1,
                minWidth: 120,
                p: 1.5,
                borderColor: theme.palette.divider,
              })}
            >
              <Typography variant="caption" color="text.secondary">
                {card.label}
              </Typography>
              <Typography variant="h5" sx={{ color: card.color, fontWeight: 800 }}>
                {card.value}
              </Typography>
            </Paper>
          ))}
        </Stack>
      </Stack>
    </Paper>
  );
}

function replaceRecommendationPlaceholders(content: string, finding: Finding): string {
  const resourceName = finding.commandName || finding.resource;
  const resourceNamespace = finding.commandNamespace || finding.namespace || 'default';
  const values: Record<string, string> = {
    name: resourceName,
    namespace: resourceNamespace,
    ns: resourceNamespace,
    pod: resourceName,
    'pod-name': resourceName,
    service: resourceName,
    'service-name': resourceName,
    resource: resourceName,
    'resource-name': resourceName,
  };

  return Object.entries(values).reduce((current, [placeholder, value]) => {
    const escapedPlaceholder = placeholder.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return current
      .replace(new RegExp(`<${escapedPlaceholder}>`, 'g'), value)
      .replace(new RegExp(`&lt;${escapedPlaceholder}&gt;`, 'g'), value);
  }, content);
}

function stripLeadingRecommendationHeading(content: string): string {
  return content
    .replace(/^\s*<div[^>]*>\s*/i, match => match)
    .replace(/^\s*(<div[^>]*>\s*)?<h[1-6][^>]*>[\s\S]*?<\/h[1-6]>\s*/i, '$1');
}

function RecommendationContent({ check, finding }: { check: CheckResult; finding: Finding }) {
  if (!check.recommendationHtml) {
    return <Typography variant="body2">{replaceRecommendationPlaceholders(check.recommendation, finding)}</Typography>;
  }

  const recommendationHtml = stripLeadingRecommendationHeading(
    replaceRecommendationPlaceholders(check.recommendationHtml, finding)
  );

  return (
    <Box
      sx={theme => ({
        '& ul': {
          margin: 0,
          pl: 2.25,
        },
        '& li': {
          mb: 1,
        },
        '& code': {
          bgcolor: theme.palette.action.hover,
          border: `1px solid ${theme.palette.divider}`,
          borderRadius: 0.5,
          color: theme.palette.text.primary,
          px: 0.5,
        },
        '& pre': {
          bgcolor: theme.palette.background.default,
          border: `1px solid ${theme.palette.divider}`,
          borderRadius: 1,
          overflow: 'auto',
          p: 1,
        },
        '& a': {
          color: theme.palette.primary.main,
        },
      })}
      dangerouslySetInnerHTML={{ __html: recommendationHtml }}
    />
  );
}

function buildAIPrompt(check: CheckResult, finding: Finding, clusterKey: string): string {
  const recommendation = replaceRecommendationPlaceholders(check.recommendation, finding);
  const docs = check.docs ? `\nDocumentation: ${check.docs}` : '';
  const namespace = finding.namespace || 'cluster scoped';
  const resourceKind = finding.kind || check.resourceKind;

  return [
    'You are helping troubleshoot a Kubernetes issue found by KubeBuddy in Headlamp.',
    '',
    'Please explain the likely cause, give safe verification steps, and suggest a practical fix.',
    'Prefer read-only kubectl commands first. Call out any risky or disruptive action before suggesting it.',
    '',
    `Cluster: ${clusterKey}`,
    `Check: ${check.id} - ${check.name}`,
    `Section: ${reportSectionLabel(check.section)}`,
    `Severity: ${check.severity}`,
    `Status: ${check.status}`,
    `Description: ${check.description}`,
    `Finding: ${finding.details}`,
    '',
    'Affected resource:',
    `- Name: ${finding.resource}`,
    `- Kind: ${resourceKind}`,
    `- Namespace: ${namespace}`,
    finding.apiVersion ? `- API version: ${finding.apiVersion}` : '',
    '',
    `KubeBuddy recommendation: ${recommendation}`,
    docs,
  ].filter(Boolean).join('\n');
}

function DrawerSectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <Stack direction="row" spacing={1} alignItems="center">
      <Box
        aria-hidden="true"
        sx={theme => ({
          bgcolor: theme.palette.primary.main,
          borderRadius: 999,
          height: 18,
          width: 3,
        })}
      />
      <Typography
        variant="subtitle1"
        sx={theme => ({
          color: theme.palette.text.primary,
          fontWeight: 800,
          letterSpacing: 0,
          lineHeight: 1.35,
        })}
      >
        {children}
      </Typography>
    </Stack>
  );
}

function FindingDetailsDrawer({
  check,
  finding,
  onClose,
}: {
  check: CheckResult;
  finding: Finding | null;
  onClose: () => void;
}) {
  const history = useHistory();
  const location = useLocation();
  const [aiPromptCopied, setAiPromptCopied] = React.useState(false);
  const clusterKey = clusterKeyFromPath(location.pathname);
  const resourceKind = finding?.kind || check.resourceKind;
  const namespaceLabel = finding?.namespace || 'Cluster scoped';
  const severityLabel = check.severity.charAt(0).toUpperCase() + check.severity.slice(1);
  const copyAIPrompt = React.useCallback(async () => {
    if (!finding) {
      return;
    }

    await navigator.clipboard.writeText(buildAIPrompt(check, finding, clusterKey));
    setAiPromptCopied(true);
    window.setTimeout(() => setAiPromptCopied(false), 1800);
  }, [check, clusterKey, finding]);
  const openInHeadlamp = React.useCallback(() => {
    if (!finding?.link) {
      return;
    }

    storeReturnTarget(clusterKey, {
      checkId: check.id,
      section: check.section,
      findingKey: findingKey(finding),
    });
    onClose();
    history.push(finding.link);
  }, [check.id, check.section, clusterKey, finding, history, onClose]);

  return (
    <Drawer
      anchor="right"
      open={Boolean(finding)}
      onClose={onClose}
      PaperProps={{
        sx: theme => ({
          bgcolor: theme.palette.background.paper,
          borderLeft: `1px solid ${theme.palette.divider}`,
          height: 'calc(100% - 64px)',
          maxWidth: 'min(560px, 100vw)',
          mt: '64px',
          width: '100%',
        }),
      }}
    >
      {finding && (
        <Stack spacing={3} sx={{ p: 3, pt: 3.5 }}>
          <Stack direction="row" justifyContent="space-between" spacing={2} alignItems="flex-start">
            <Box sx={{ minWidth: 0 }}>
              <Typography variant="overline" color="text.secondary">
                {check.id} · {reportSectionLabel(check.section)} · {severityLabel}
              </Typography>
              <Typography variant="h5" sx={{ overflowWrap: 'anywhere' }}>
                {check.name}
              </Typography>
            </Box>
            <IconButton aria-label="Close finding details" onClick={onClose} size="small">
              X
            </IconButton>
          </Stack>

          <Stack spacing={1}>
            <DrawerSectionHeading>Finding</DrawerSectionHeading>
            <Paper variant="outlined" sx={{ p: 2 }}>
              <Stack spacing={1.25}>
                <Typography variant="body1" sx={{ fontWeight: 700 }}>
                  {finding.details}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  {check.description}
                </Typography>
                <Typography variant="body2">
                  {replaceRecommendationPlaceholders(check.recommendation, finding)}
                </Typography>
              </Stack>
            </Paper>
          </Stack>

          <Stack spacing={1}>
            <DrawerSectionHeading>Affected Resource</DrawerSectionHeading>
            <Paper variant="outlined" sx={{ p: 2 }}>
              <Stack spacing={1.5}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block', fontWeight: 700 }}>
                    Name
                  </Typography>
                  <Typography variant="body1" sx={{ fontWeight: 700, overflowWrap: 'anywhere' }}>
                    {finding.resource}
                  </Typography>
                </Box>
                <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
                  <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography variant="caption" color="text.secondary" sx={{ display: 'block', fontWeight: 700 }}>
                      Kind
                    </Typography>
                    <Typography variant="body2">{resourceKind}</Typography>
                  </Box>
                  <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography variant="caption" color="text.secondary" sx={{ display: 'block', fontWeight: 700 }}>
                      Namespace
                    </Typography>
                    <Typography variant="body2">{namespaceLabel}</Typography>
                  </Box>
                </Stack>
              </Stack>
            </Paper>
          </Stack>

          <Stack spacing={1}>
            <DrawerSectionHeading>Recommended Fix</DrawerSectionHeading>
            <Paper variant="outlined" sx={{ p: 2 }}>
              <RecommendationContent check={check} finding={finding} />
            </Paper>
          </Stack>

          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} flexWrap="wrap">
            {finding.link && (
              <Button onClick={openInHeadlamp} variant="contained">
                View Resource
              </Button>
            )}
            <Button onClick={copyAIPrompt} variant="outlined">
              {aiPromptCopied ? 'Copied' : 'Copy AI Prompt'}
            </Button>
            {check.docs && (
              <Button href={check.docs} target="_blank" rel="noreferrer" variant="outlined">
                Kubernetes Docs
              </Button>
            )}
          </Stack>
        </Stack>
      )}
    </Drawer>
  );
}

type FindingsSortColumn = 'resource' | 'namespace' | 'details';
type FindingsSortDirection = 'asc' | 'desc';

function findingSortValue(check: CheckResult, finding: Finding, column: FindingsSortColumn): string {
  if (column === 'resource') {
    return `${finding.resource} ${finding.kind || check.resourceKind}`.toLowerCase();
  }
  if (column === 'namespace') {
    return (finding.namespace || 'cluster scoped').toLowerCase();
  }
  return finding.details.toLowerCase();
}

function FindingsTable({
  check,
  findings,
  returnFindingKey,
}: {
  check: CheckResult;
  findings: Finding[];
  returnFindingKey?: string;
}) {
  const [sortColumn, setSortColumn] = React.useState<FindingsSortColumn>('resource');
  const [sortDirection, setSortDirection] = React.useState<FindingsSortDirection>('asc');
  const restoredFinding = React.useMemo(
    () => findings.find(item => returnFindingKey && findingKey(item) === returnFindingKey) || null,
    [findings, returnFindingKey]
  );
  const [selectedFinding, setSelectedFinding] = React.useState<Finding | null>(restoredFinding);
  const sortedFindings = React.useMemo(() => {
    return [...findings].sort((left, right) => {
      const comparison = findingSortValue(check, left, sortColumn).localeCompare(
        findingSortValue(check, right, sortColumn),
        undefined,
        { numeric: true, sensitivity: 'base' }
      );
      return sortDirection === 'asc' ? comparison : -comparison;
    });
  }, [check, findings, sortColumn, sortDirection]);
  const requestSort = (column: FindingsSortColumn) => {
    if (sortColumn === column) {
      setSortDirection(current => (current === 'asc' ? 'desc' : 'asc'));
      return;
    }

    setSortColumn(column);
    setSortDirection('asc');
  };
  const sortLabel = (column: FindingsSortColumn, label: string) => (
    <TableSortLabel
      active={sortColumn === column}
      direction={sortColumn === column ? sortDirection : 'asc'}
      onClick={() => requestSort(column)}
    >
      {label}
    </TableSortLabel>
  );

  React.useEffect(() => {
    if (restoredFinding) {
      setSelectedFinding(restoredFinding);
    }
  }, [restoredFinding]);

  if (findings.length === 0) {
    return <Typography color="success.main">No issues detected.</Typography>;
  }

  return (
    <>
      <TableContainer
        component={Paper}
        variant="outlined"
        sx={theme => ({
          bgcolor: theme.palette.background.default,
          borderColor: theme.palette.divider,
          '& .MuiTableCell-root': {
            borderColor: theme.palette.divider,
          },
          '& .MuiTableHead-root .MuiTableCell-root': {
            bgcolor: theme.palette.action.hover,
            color: theme.palette.text.primary,
            fontWeight: 800,
          },
          '& .MuiTableSortLabel-root': {
            color: `${theme.palette.text.primary} !important`,
            fontWeight: 800,
          },
          '& .MuiTableSortLabel-icon': {
            color: `${theme.palette.text.secondary} !important`,
          },
          '& .MuiTableBody-root .MuiTableRow-root': {
            cursor: 'pointer',
          },
          '& .MuiTableBody-root .MuiTableRow-root:hover': {
            bgcolor: theme.palette.action.selected,
          },
          '& .MuiTableBody-root .MuiTableRow-root:nth-of-type(odd)': {
            bgcolor: theme.palette.action.hover,
          },
        })}
      >
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell sortDirection={sortColumn === 'resource' ? sortDirection : false}>
                {sortLabel('resource', 'Resource')}
              </TableCell>
              <TableCell sortDirection={sortColumn === 'namespace' ? sortDirection : false}>
                {sortLabel('namespace', 'Namespace')}
              </TableCell>
              <TableCell sortDirection={sortColumn === 'details' ? sortDirection : false}>
                {sortLabel('details', 'Details')}
              </TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {sortedFindings.map((item, index) => (
              <TableRow
                hover
                key={`${item.resource}-${item.namespace || 'cluster'}-${index}`}
                onClick={() => setSelectedFinding(item)}
                tabIndex={0}
                onKeyDown={event => {
                  if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    setSelectedFinding(item);
                  }
                }}
              >
                <TableCell>
                  <Stack spacing={0.25}>
                    <Link
                      component="button"
                      onClick={event => {
                        event.stopPropagation();
                        setSelectedFinding(item);
                      }}
                      sx={{ textAlign: 'left' }}
                    >
                      {item.resource}
                    </Link>
                    <Typography variant="caption" color="text.secondary">
                      {item.kind || check.resourceKind}
                    </Typography>
                  </Stack>
                </TableCell>
                <TableCell>{item.namespace || '-'}</TableCell>
                <TableCell>{item.details}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
      <FindingDetailsDrawer
        check={check}
        finding={selectedFinding}
        onClose={() => setSelectedFinding(null)}
      />
    </>
  );
}

function CheckCard({ check, returnFindingKey }: { check: CheckResult; returnFindingKey?: string }) {
  const failed = check.status === 'failed';
  const skipped = check.status === 'skipped';
  const alertSeverity = severityColor(check.severity);
  const [open, setOpen] = React.useState(failed || Boolean(returnFindingKey));
  React.useEffect(() => {
    if (returnFindingKey) {
      setOpen(true);
    }
  }, [returnFindingKey]);
  const findingAlertSx = (theme: Theme) => ({
    bgcolor: theme.palette.action.hover,
    border: `1px solid ${theme.palette.divider}`,
    color: theme.palette.text.primary,
    '& .MuiAlert-icon': {
      color: theme.palette[alertSeverity].main,
    },
    '& .MuiAlert-message': {
      color: theme.palette.text.primary,
    },
  });
  const skippedAlertSx = (theme: Theme) => ({
    bgcolor: theme.palette.action.hover,
    border: `1px solid ${theme.palette.divider}`,
    color: theme.palette.text.primary,
    '& .MuiAlert-icon': {
      color: theme.palette.info.main,
    },
    '& .MuiAlert-message': {
      color: theme.palette.text.primary,
    },
  });
  const toggleOpen = () => setOpen(current => !current);
  const handleHeaderKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      toggleOpen();
    }
  };

  return (
    <Paper variant="outlined" sx={{ p: 2 }}>
      <Stack spacing={1.5}>
        <Stack
          direction="row"
          justifyContent="space-between"
          onClick={toggleOpen}
          onKeyDown={handleHeaderKeyDown}
          role="button"
          spacing={1}
          sx={theme => ({
            borderRadius: 1,
            cursor: 'pointer',
            mx: -1,
            p: 1,
            transition: theme.transitions.create('background-color', { duration: theme.transitions.duration.shortest }),
            '&:hover': {
              bgcolor: theme.palette.action.hover,
            },
            '&:focus-visible': {
              outline: `2px solid ${theme.palette.primary.main}`,
              outlineOffset: 2,
            },
          })}
          tabIndex={0}
        >
          <Stack direction="row" spacing={1.25} sx={{ minWidth: 0, flex: 1 }}>
            <Box sx={{ minWidth: 0 }}>
              <Stack direction="row" spacing={1} flexWrap="wrap" alignItems="center">
                <Typography variant="h6" sx={{ overflowWrap: 'anywhere' }}>
                  {check.name}
                </Typography>
                <Chip size="small" variant="outlined" label={check.id} />
                <Chip
                  size="small"
                  color={skipped ? 'default' : failed ? severityColor(check.severity) : 'success'}
                  label={skipped ? 'skipped' : failed ? check.severity : 'passed'}
                />
                <Chip size="small" variant="outlined" label={`${check.findings.length} findings`} />
                {check.nativeHandler && <Chip size="small" variant="outlined" label={check.nativeHandler} />}
              </Stack>
              <Typography variant="body2" color="text.secondary">{check.description}</Typography>
            </Box>
          </Stack>
          <Stack direction="row" spacing={0.5} alignItems="center" sx={{ alignSelf: 'flex-start' }}>
            {check.docs && (
              <Tooltip title="Open documentation">
                <IconButton
                  aria-label={`Open documentation for ${check.id}`}
                  href={check.docs}
                  target="_blank"
                  rel="noreferrer"
                  onClick={event => event.stopPropagation()}
                  size="small"
                >
                  <DocsIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            )}
            <Tooltip title={open ? 'Collapse findings' : 'Expand findings'}>
              <IconButton
                aria-expanded={open}
                aria-label={`${open ? 'Collapse' : 'Expand'} ${check.id}`}
                onClick={event => {
                  event.stopPropagation();
                  toggleOpen();
                }}
                size="small"
              >
                <ExpandDownIcon
                  fontSize="small"
                  sx={{
                    transform: open ? 'rotate(180deg)' : 'rotate(0deg)',
                  }}
                />
              </IconButton>
            </Tooltip>
          </Stack>
        </Stack>
        {open && (
          <Stack spacing={1.5}>
            {failed && <Alert severity={alertSeverity} sx={findingAlertSx}>{check.recommendation}</Alert>}
            {skipped && <Alert severity="info" sx={skippedAlertSx}>{check.skippedReason}</Alert>}
            {!skipped && <FindingsTable check={check} findings={check.findings} returnFindingKey={returnFindingKey} />}
          </Stack>
        )}
      </Stack>
    </Paper>
  );
}

function reportSectionRank(section: string): number {
  const normalized = section.trim().toLowerCase();
  const order = [
    'all',
    'workloads',
    'nodes',
    'pods',
    'jobs',
    'networking',
    'storage',
    'namespaces',
    'configuration hygiene',
    'security',
    'kubernetes events',
  ];
  const index = order.indexOf(normalized);

  return index === -1 ? order.length : index;
}

function reportSectionLabel(section: string): string {
  if (section === 'All') {
    return 'All';
  }
  if (section === 'Configuration') {
    return 'Configuration Hygiene';
  }
  if (section === 'Kubernetes Warning Events') {
    return 'Kubernetes Events';
  }
  return section;
}

function SectionTabLabel({ label, failedCount }: { label: string; failedCount: number }) {
  return (
    <Stack component="span" direction="row" spacing={0.75} alignItems="center">
      <Box component="span">{label}</Box>
      {failedCount > 0 && (
        <Box
          component="span"
          sx={theme => ({
            alignItems: 'center',
            bgcolor: theme.palette.error.main,
            borderRadius: 999,
            color: theme.palette.error.contrastText,
            display: 'inline-flex',
            fontSize: '0.7rem',
            fontWeight: 800,
            height: 18,
            justifyContent: 'center',
            lineHeight: 1,
            minWidth: 18,
            px: 0.6,
          })}
        >
          {failedCount > 99 ? '99+' : failedCount}
        </Box>
      )}
    </Stack>
  );
}

function CheckFilterBar({
  severity,
  severityCounts,
  status,
  statusCounts,
  onClearAll,
  onSeverityChange,
  onStatusChange,
}: {
  severity: SeverityFilter;
  severityCounts: Record<SeverityFilter, number>;
  status: StatusFilter;
  statusCounts: Record<StatusFilter, number>;
  onClearAll: () => void;
  onSeverityChange: (severity: SeverityFilter) => void;
  onStatusChange: (status: StatusFilter) => void;
}) {
  const statusItems: { label: string; value: StatusFilter; color: 'primary' | 'error' | 'success' | 'warning' }[] = [
    { label: `Failed ${statusCounts.failed}`, value: 'failed', color: 'error' },
    { label: `Passed ${statusCounts.passed}`, value: 'passed', color: 'success' },
    { label: `Skipped ${statusCounts.skipped}`, value: 'skipped', color: 'warning' },
  ];
  const severityItems: { label: string; value: SeverityFilter; color: 'primary' | 'error' | 'warning' | 'info' | 'success' }[] = [
    { label: `High ${severityCounts.high}`, value: 'high', color: 'error' },
    { label: `Warning ${severityCounts.warning}`, value: 'warning', color: 'warning' },
    { label: `Medium ${severityCounts.medium}`, value: 'medium', color: 'info' },
    { label: `Low ${severityCounts.low}`, value: 'low', color: 'success' },
  ];

  const renderItem = <T extends StatusFilter | SeverityFilter>(
    item: { label: string; value: T; color: 'primary' | 'error' | 'success' | 'warning' | 'info' },
    selectedValue: T,
    onClick: (value: T) => void
  ) => (
    <Button
      color={item.color}
      key={item.value}
      onClick={() => onClick(item.value)}
      size="small"
      variant={selectedValue === item.value ? 'contained' : 'text'}
      sx={{ minHeight: 30, textTransform: 'none', whiteSpace: 'nowrap' }}
    >
      {item.label}
    </Button>
  );

  return (
    <Stack
      direction="row"
      flexWrap="wrap"
      spacing={1.25}
      useFlexGap
      sx={theme => ({
        alignItems: 'center',
        border: `1px solid ${theme.palette.divider}`,
        borderRadius: 1,
        display: 'inline-flex',
        p: 0.5,
      })}
    >
      <Stack direction="row" spacing={0.5} alignItems="center" flexWrap="wrap" useFlexGap>
        <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 700, px: 0.75 }}>
          Status
        </Typography>
        <Button
          color="primary"
          onClick={onClearAll}
          size="small"
          variant={status === 'all' && severity === 'all' ? 'contained' : 'text'}
          sx={{ minHeight: 30, textTransform: 'none', whiteSpace: 'nowrap' }}
        >
          All {statusCounts.all}
        </Button>
        {statusItems.map(item => renderItem(item, status, onStatusChange))}
      </Stack>
      <Box
        aria-hidden="true"
        sx={theme => ({
          alignSelf: 'stretch',
          borderLeft: `1px solid ${theme.palette.divider}`,
          display: { xs: 'none', sm: 'block' },
          minHeight: 28,
        })}
      />
      <Stack direction="row" spacing={0.5} alignItems="center" flexWrap="wrap" useFlexGap>
        <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 700, px: 0.75 }}>
          Severity
        </Typography>
        {severityItems.map(item => renderItem(item, severity, onSeverityChange))}
      </Stack>
    </Stack>
  );
}

function LoadingResourcesState() {
  return (
    <Paper variant="outlined" sx={{ p: 3 }}>
      <Stack direction="row" spacing={1.5} alignItems="center">
        <CircularProgress size={22} />
        <Box>
          <Typography variant="body1">Loading cluster resources</Typography>
          <Typography variant="body2" color="text.secondary">
            KubeBuddy results will appear once Headlamp has loaded every resource list used by the checks.
          </Typography>
        </Box>
      </Stack>
    </Paper>
  );
}

function ReadyToScanState({ onStart }: { onStart: () => void }) {
  return (
    <Paper variant="outlined" sx={{ minHeight: 260, p: 4 }}>
      <Stack spacing={3} alignItems="center" justifyContent="center" sx={{ minHeight: 220, textAlign: 'center' }}>
        <Box sx={{ maxWidth: 620 }}>
          <Typography variant="body1">Ready to scan this cluster.</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.75 }}>
            The scan runs in this Headlamp page after you start it. Keep the page open until it finishes.
          </Typography>
        </Box>
        <Button
          size="large"
          variant="contained"
          onClick={onStart}
          sx={{ borderRadius: 2, fontSize: '1rem', fontWeight: 800, minHeight: 52, px: 5 }}
        >
          Start Scan
        </Button>
      </Stack>
    </Paper>
  );
}

function NamespaceExclusionsControl({
  config,
  onChange,
}: {
  config: KubeBuddyConfig;
  onChange: (config: KubeBuddyConfig) => void;
}) {
  const namespaces = useResourceList<any>(K8s.ResourceClasses.Namespace.useList());
  const namespaceOptions = React.useMemo(
    () => normalizeNamespaceList(namespaces.data.map(item => name(item))),
    [namespaces.data]
  );

  const updateAdditionalNamespaces = (_: React.SyntheticEvent, values: string[]) => {
    onChange({
      ...config,
      additionalExcludedNamespaces: normalizeNamespaceList(values),
      excludedNamespaces: effectiveExcludedNamespaces({
        useSystemNamespaceExclusions: config.useSystemNamespaceExclusions,
        additionalExcludedNamespaces: values,
      }),
    });
  };

  const updateSystemNamespaces = (enabled: boolean) => {
    onChange({
      ...config,
      useSystemNamespaceExclusions: enabled,
      excludedNamespaces: effectiveExcludedNamespaces({
        useSystemNamespaceExclusions: enabled,
        additionalExcludedNamespaces: config.additionalExcludedNamespaces,
      }),
    });
  };

  return (
    <Paper variant="outlined" sx={{ p: 2 }}>
      <Stack spacing={1.5}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} justifyContent="space-between">
          <Box>
            <Typography variant="subtitle2" sx={{ fontWeight: 800 }}>
              Namespace exclusions
            </Typography>
            <Typography variant="body2" color="text.secondary">
              Skip system namespaces and any extra namespaces you select before scanning.
            </Typography>
          </Box>
          <Tooltip title={config.excludedNamespaces.length ? config.excludedNamespaces.join(', ') : 'No namespaces excluded'}>
            <Chip label={`${config.excludedNamespaces.length} excluded`} size="small" />
          </Tooltip>
        </Stack>
        <FormControlLabel
          control={
            <Checkbox
              checked={config.useSystemNamespaceExclusions}
              onChange={event => updateSystemNamespaces(event.target.checked)}
            />
          }
          label="Exclude KubeBuddy system namespaces"
        />
        <Autocomplete
          freeSolo
          multiple
          options={namespaceOptions}
          value={config.additionalExcludedNamespaces}
          onChange={updateAdditionalNamespaces}
          renderInput={params => (
            <TextField
              {...params}
              label="Additional namespaces"
              placeholder="Select or type namespace"
              size="small"
            />
          )}
        />
      </Stack>
    </Paper>
  );
}

function NamespaceExclusionsSummary({ namespaces }: { namespaces: string[] }) {
  const visibleNamespaces = namespaces.slice(0, 8);
  const hiddenNamespaces = namespaces.slice(8);
  const remaining = Math.max(0, namespaces.length - visibleNamespaces.length);

  return (
    <Paper variant="outlined" sx={{ p: 1.5 }}>
      <Stack direction={{ xs: 'column', md: 'row' }} spacing={1.25} alignItems={{ xs: 'stretch', md: 'center' }} justifyContent="space-between">
        <Box>
          <Typography variant="subtitle2" sx={{ fontWeight: 800 }}>
            Namespace exclusions used
          </Typography>
          <Typography variant="body2" color="text.secondary">
            This completed scan skipped the namespaces listed below.
          </Typography>
        </Box>
        <Stack direction="row" spacing={0.75} flexWrap="wrap" useFlexGap>
          {visibleNamespaces.map(namespace => (
            <Chip key={namespace} label={namespace} size="small" variant="outlined" />
          ))}
          {remaining > 0 && (
            <Tooltip title={hiddenNamespaces.join(', ')}>
              <Chip label={`+${remaining} more`} size="small" />
            </Tooltip>
          )}
          {namespaces.length === 0 && <Chip label="None" size="small" variant="outlined" />}
        </Stack>
      </Stack>
    </Paper>
  );
}

function severityRank(severity: Severity): number {
  const ranks: Record<Severity, number> = {
    high: 0,
    warning: 1,
    medium: 2,
    low: 3,
  };

  return ranks[severity];
}

function ReportSummary({
  checks,
  excludedNamespaces,
  onOpenSection,
}: {
  checks: CheckResult[];
  excludedNamespaces: string[];
  onOpenSection: (section: string) => void;
}) {
  const failedChecks = React.useMemo(
    () =>
      checks
        .filter(check => check.status === 'failed')
        .sort((left, right) => {
          const severityDelta = severityRank(left.severity) - severityRank(right.severity);
          return severityDelta || right.weight - left.weight || left.id.localeCompare(right.id);
        }),
    [checks]
  );
  const sectionBreakdown = React.useMemo(
    () =>
      Array.from(new Set(checks.map(check => check.section)))
        .map(section => {
          const sectionChecks = checks.filter(check => check.section === section);
          return {
            failed: sectionChecks.filter(check => check.status === 'failed').length,
            label: reportSectionLabel(section),
            section,
            total: sectionChecks.length,
          };
        })
        .sort((left, right) => right.failed - left.failed || reportSectionRank(left.label) - reportSectionRank(right.label)),
    [checks]
  );
  const topFailedChecks = failedChecks.slice(0, 6);

  return (
    <Stack spacing={2}>
      <ScoreHero checks={checks} />
      <NamespaceExclusionsSummary namespaces={excludedNamespaces} />

      <Stack direction={{ xs: 'column', lg: 'row' }} spacing={2}>
        <Paper variant="outlined" sx={{ flex: 1, p: 2 }}>
          <Stack spacing={1.5}>
            <Box>
              <Typography variant="subtitle2" sx={{ fontWeight: 800 }}>
                Highest priority failed checks
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Start with checks that have higher severity and score weight.
              </Typography>
            </Box>
            {topFailedChecks.length ? (
              <Stack spacing={1}>
                {topFailedChecks.map(check => (
                  <Stack
                    key={check.id}
                    direction={{ xs: 'column', sm: 'row' }}
                    spacing={1}
                    alignItems={{ xs: 'stretch', sm: 'center' }}
                    justifyContent="space-between"
                    sx={theme => ({
                      border: `1px solid ${theme.palette.divider}`,
                      borderRadius: 1,
                      p: 1,
                    })}
                  >
                    <Box sx={{ minWidth: 0 }}>
                      <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap">
                        <Chip size="small" variant="outlined" label={check.id} />
                        <Chip size="small" color={severityColor(check.severity)} label={check.severity} />
                        <Chip size="small" variant="outlined" label={`${check.findings.length} findings`} />
                      </Stack>
                      <Typography variant="body2" sx={{ fontWeight: 700, mt: 0.5, overflowWrap: 'anywhere' }}>
                        {check.name}
                      </Typography>
                      <Typography variant="caption" color="text.secondary">
                        {reportSectionLabel(check.section)}
                      </Typography>
                    </Box>
                    <Button size="small" onClick={() => onOpenSection(check.section)}>
                      View
                    </Button>
                  </Stack>
                ))}
              </Stack>
            ) : (
              <Alert severity="success">No failed checks in this scan.</Alert>
            )}
          </Stack>
        </Paper>

        <Paper variant="outlined" sx={{ flex: 1, p: 2 }}>
          <Stack spacing={1.5}>
            <Box>
              <Typography variant="subtitle2" sx={{ fontWeight: 800 }}>
                Section breakdown
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Failed checks by report section.
              </Typography>
            </Box>
            <Stack spacing={1}>
              {sectionBreakdown.map(item => (
                <Stack
                  key={item.section}
                  direction="row"
                  spacing={1}
                  alignItems="center"
                  justifyContent="space-between"
                >
                  <Button
                    size="small"
                    onClick={() => onOpenSection(item.section)}
                    sx={{ justifyContent: 'flex-start', minWidth: 0, textAlign: 'left' }}
                  >
                    {item.label}
                  </Button>
                  <Stack direction="row" spacing={0.75} alignItems="center">
                    <Chip
                      color={item.failed > 0 ? 'error' : 'success'}
                      label={`${item.failed} failed`}
                      size="small"
                      variant={item.failed > 0 ? 'filled' : 'outlined'}
                    />
                    <Typography variant="caption" color="text.secondary">
                      {item.total} checks
                    </Typography>
                  </Stack>
                </Stack>
              ))}
            </Stack>
          </Stack>
        </Paper>
      </Stack>
    </Stack>
  );
}

function KubeBuddyAdvancedConfigControl({
  config,
  onChange,
}: {
  config: KubeBuddyConfig;
  onChange: (config: KubeBuddyConfig) => void;
}) {
  const pods = useResourceList<any>(K8s.ResourceClasses.Pod.useList());
  const registryOptions = React.useMemo(
    () =>
      normalizeRegistries(
        pods.data.flatMap(pod =>
          containers(pod, false).map(container => imageRegistryPrefix(String(container.image || '')))
        )
      ),
    [pods.data]
  );
  const updateThreshold = (key: keyof KubeBuddyConfig['thresholds'], value: string) => {
    onChange({
      ...config,
      thresholds: {
        ...config.thresholds,
        [key]: Number(value),
      },
    });
  };
  const checkOptions = React.useMemo(
    () => KUBERNETES_CHECKS.map(check => ({ id: check.id, label: `${check.id} - ${check.name}` })),
    []
  );
  const selectedExcludedChecks = React.useMemo(
    () => checkOptions.filter(option => config.excludedChecks.includes(option.id)),
    [checkOptions, config.excludedChecks]
  );

  return (
    <Paper variant="outlined" sx={{ p: 2 }}>
      <Stack spacing={2}>
        <Box>
          <Typography variant="subtitle2" sx={{ fontWeight: 800 }}>
            Trusted registries
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
            Images outside these prefixes are reported by the untrusted registry check. KubeBuddy uses
            prefix matching here, not regex.
          </Typography>
          <Autocomplete
            freeSolo
            multiple
            options={registryOptions}
            value={config.trustedRegistries}
            onChange={(_, values) =>
              onChange({ ...config, trustedRegistries: normalizeRegistries(values) })
            }
            renderInput={params => (
              <TextField
                {...params}
                helperText="Select a registry seen in running pod images, or type a prefix. Short Docker Hub images are shown as docker.io/library/. Examples: mcr.microsoft.com/, docker.io/library/, ghcr.io/my-org/."
                placeholder={registryOptions.length > 0 ? 'Select or type a prefix' : 'mcr.microsoft.com/'}
                size="small"
              />
            )}
          />
        </Box>
        <Divider />
        <Box>
          <Typography variant="subtitle2" sx={{ fontWeight: 800 }}>
            Excluded checks
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
            Selected checks are skipped during scans, matching the CLI excluded checks behavior.
          </Typography>
          <Autocomplete
            multiple
            options={checkOptions}
            value={selectedExcludedChecks}
            getOptionLabel={option => option.label}
            isOptionEqualToValue={(option, value) => option.id === value.id}
            onChange={(_, values) => onChange({ ...config, excludedChecks: values.map(value => value.id).sort() })}
            renderInput={params => (
              <TextField
                {...params}
                placeholder="Select checks to skip"
                size="small"
              />
            )}
          />
        </Box>
        <Divider />
        <Box>
          <Typography variant="subtitle2" sx={{ fontWeight: 800, mb: 1 }}>
            Thresholds
          </Typography>
        <Stack direction={{ xs: 'column', md: 'row' }} spacing={1.5}>
          <TextField label="Restart warning" size="small" type="number" value={config.thresholds.restartsWarning} onChange={event => updateThreshold('restartsWarning', event.target.value)} />
          <TextField label="Restart critical" size="small" type="number" value={config.thresholds.restartsCritical} onChange={event => updateThreshold('restartsCritical', event.target.value)} />
          <TextField label="Pod age days" size="small" type="number" value={config.thresholds.podAgeWarning} onChange={event => updateThreshold('podAgeWarning', event.target.value)} />
          <TextField label="Stuck job hours" size="small" type="number" value={config.thresholds.stuckJobHours} onChange={event => updateThreshold('stuckJobHours', event.target.value)} />
          <TextField label="Pods per node %" size="small" type="number" value={config.thresholds.podsPerNodeCritical} onChange={event => updateThreshold('podsPerNodeCritical', event.target.value)} />
        </Stack>
        </Box>
      </Stack>
    </Paper>
  );
}

function ScanLogPanel({ logs }: { logs: ScanLogEntry[] }) {
  const logRef = React.useRef<HTMLDivElement | null>(null);

  React.useEffect(() => {
    if (logRef.current) {
      logRef.current.scrollTop = logRef.current.scrollHeight;
    }
  }, [logs]);

  return (
    <Paper
      ref={logRef}
      variant="outlined"
      sx={theme => ({
        bgcolor: theme.palette.background.default,
        borderColor: theme.palette.divider,
        color: theme.palette.text.primary,
        fontFamily: 'Consolas, Monaco, "Courier New", monospace',
        fontSize: '0.82rem',
        lineHeight: 1.55,
        maxHeight: 240,
        overflow: 'auto',
        p: 1.5,
        whiteSpace: 'nowrap',
      })}
    >
      {logs.length ? (
        logs.map(log => (
          <Box key={log.id} sx={{ minWidth: 'max-content' }}>
            <Box component="span" sx={{ color: 'text.secondary' }}>
              [{log.timestamp}]
            </Box>
            <Box component="span" sx={{ color: logLevelColor(log.level), fontWeight: log.level === 'info' ? 500 : 700, ml: 1 }}>
              {log.message}
            </Box>
          </Box>
        ))
      ) : (
        <Box>Waiting for scan output.</Box>
      )}
    </Paper>
  );
}

function useScanNavigationGuard(scanning: boolean): JSX.Element {
  const history = useHistory();
  const [pendingPath, setPendingPath] = React.useState<string | null>(null);
  const unblockRef = React.useRef<(() => void) | null>(null);

  React.useEffect(() => {
    if (!scanning) {
      if (unblockRef.current) {
        unblockRef.current();
        unblockRef.current = null;
      }
      setPendingPath(null);
      return undefined;
    }

    unblockRef.current = history.block(location => {
      const nextPath = `${location.pathname}${location.search || ''}${location.hash || ''}`;
      const currentPath = `${history.location.pathname}${history.location.search || ''}${history.location.hash || ''}`;

      if (nextPath === currentPath) {
        return undefined;
      }

      setPendingPath(nextPath);
      return false;
    });

    return () => {
      if (unblockRef.current) {
        unblockRef.current();
        unblockRef.current = null;
      }
    };
  }, [history, scanning]);

  const stayOnPage = () => setPendingPath(null);
  const leavePage = () => {
    const nextPath = pendingPath;

    if (unblockRef.current) {
      unblockRef.current();
      unblockRef.current = null;
    }

    setPendingPath(null);

    if (nextPath) {
      history.push(nextPath);
    }
  };

  return (
    <Dialog open={Boolean(pendingPath)} onClose={stayOnPage}>
      <DialogTitle>Leave KubeBuddy scan?</DialogTitle>
      <DialogContent>
        <DialogContentText>
          KubeBuddy is still scanning in this page. Leaving now stops the scan and discards the current run.
        </DialogContentText>
      </DialogContent>
      <DialogActions>
        <Button onClick={stayOnPage}>Stay</Button>
        <Button color="warning" variant="contained" onClick={leavePage}>
          Leave Page
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function KubeBuddyScanResults({
  clusterKey,
  config,
  excludedNamespaces,
  initialReport,
  onScanComplete,
}: {
  clusterKey: string;
  config: KubeBuddyConfig;
  excludedNamespaces: string[];
  initialReport?: StoredReport | null;
  onScanComplete?: (report: StoredReport) => void;
}) {
  const [returnTarget] = React.useState<KubeBuddyReturnTarget | null>(() => consumeReturnTarget(clusterKey));
  const usingStoredReport = Boolean(initialReport?.checks.length);
  const activeCheckCount = KUBERNETES_CHECKS.length - config.excludedChecks.length;
  const { checks, loading, errors, scanning, scanProgress, scanLogs } = useKubeBuddyChecks(
    !usingStoredReport,
    initialReport?.checks,
    config
  );
  const navigationGuard = useScanNavigationGuard(scanning);
  const [section, setSection] = React.useState(returnTarget?.section || 'Summary');
  const [status, setStatus] = React.useState<StatusFilter>('all');
  const [severity, setSeverity] = React.useState<SeverityFilter>('all');
  const sections = ['Summary', 'All', ...Array.from(new Set(checks.map(check => check.section))).sort((left, right) => {
    const leftLabel = reportSectionLabel(left);
    const rightLabel = reportSectionLabel(right);
    const rankDelta = reportSectionRank(leftLabel) - reportSectionRank(rightLabel);

    return rankDelta || leftLabel.localeCompare(rightLabel);
  })];
  const failedCountsBySection = React.useMemo(
    () =>
      checks.reduce<Record<string, number>>(
        (counts, check) => {
          if (check.status !== 'failed') {
            return counts;
          }

          counts.All = (counts.All || 0) + 1;
          counts[check.section] = (counts[check.section] || 0) + 1;
          return counts;
        },
        { All: 0 }
      ),
    [checks]
  );
  const detailSection = section === 'Summary' ? 'All' : section;
  const sectionChecks = detailSection === 'All' ? checks : checks.filter(check => check.section === detailSection);
  const statusFilteredChecks =
    status === 'all' ? sectionChecks : sectionChecks.filter(check => check.status === status);
  const visibleChecks =
    severity === 'all' ? statusFilteredChecks : statusFilteredChecks.filter(check => check.severity === severity);
  const statusCounts = React.useMemo<Record<StatusFilter, number>>(
    () => ({
      all: sectionChecks.length,
      failed: sectionChecks.filter(check => check.status === 'failed').length,
      passed: sectionChecks.filter(check => check.status === 'passed').length,
      skipped: sectionChecks.filter(check => check.status === 'skipped').length,
    }),
    [sectionChecks]
  );
  const severityCounts = React.useMemo<Record<SeverityFilter, number>>(
    () => ({
      all: statusFilteredChecks.length,
      high: statusFilteredChecks.filter(check => check.severity === 'high').length,
      warning: statusFilteredChecks.filter(check => check.severity === 'warning').length,
      medium: statusFilteredChecks.filter(check => check.severity === 'medium').length,
      low: statusFilteredChecks.filter(check => check.severity === 'low').length,
    }),
    [statusFilteredChecks]
  );

  React.useEffect(() => {
    setStatus('all');
    setSeverity('all');
  }, [section]);

  React.useEffect(() => {
    if (!usingStoredReport && !loading && !scanning && checks.length > 0) {
      const report = storeReport(clusterKey, checks, config);
      onScanComplete?.(report);
    }
  }, [checks, clusterKey, config, loading, onScanComplete, scanning, usingStoredReport]);

  React.useEffect(() => {
    if (!scanning) {
      return undefined;
    }

    const warnBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = 'KubeBuddy is still scanning. Leave this page and the scan will stop.';
    };

    window.addEventListener('beforeunload', warnBeforeUnload);

    return () => {
      window.removeEventListener('beforeunload', warnBeforeUnload);
    };
  }, [scanning]);

  return (
    <Stack spacing={2.5}>
      {navigationGuard}

      {errors.map((error, index) => (
        <Alert severity="error" key={`${error}-${index}`}>{error}</Alert>
      ))}

      {loading ? (
        <LoadingResourcesState />
      ) : scanning ? (
        <Paper variant="outlined" sx={{ p: 3 }}>
          <Stack spacing={1.5}>
            <Alert
              severity="warning"
              sx={theme => ({
                bgcolor: theme.palette.action.hover,
                border: `1px solid ${theme.palette.divider}`,
                color: theme.palette.text.primary,
                '& .MuiAlert-icon': {
                  color: theme.palette.warning.main,
                },
              })}
            >
              Keep this page open until the scan completes. Browser-based scans stop if you leave this page, refresh, or close Headlamp.
            </Alert>
            <Stack direction="row" spacing={1.5} alignItems="center">
              <CircularProgress size={22} />
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography variant="body1">Scanning cluster</Typography>
                <Typography variant="body2" color="text.secondary">
                  Running checks in this page. {checks.length} of {activeCheckCount} checks complete.
                </Typography>
              </Box>
              <Typography variant="body2" color="text.secondary" sx={{ fontWeight: 700 }}>
                {scanProgress}%
              </Typography>
            </Stack>
            <LinearProgress
              color="primary"
              variant="determinate"
              value={scanProgress}
              sx={theme => ({
                bgcolor: theme.palette.action.disabledBackground,
                borderRadius: 999,
                height: 8,
              })}
            />
            <ScanLogPanel logs={scanLogs} />
          </Stack>
        </Paper>
      ) : (
        <>
          <Tabs
            allowScrollButtonsMobile
            scrollButtons="auto"
            value={section}
            variant="scrollable"
            onChange={(_, value) => setSection(value)}
            sx={{
              borderBottom: theme => `1px solid ${theme.palette.divider}`,
              minHeight: 42,
              '& .MuiTab-root': {
                minHeight: 42,
                px: 2,
                textTransform: 'none',
              },
            }}
          >
            {sections.map(item => (
              <Tab
                key={item}
                label={<SectionTabLabel label={reportSectionLabel(item)} failedCount={item === 'Summary' ? failedCountsBySection.All || 0 : failedCountsBySection[item] || 0} />}
                value={item}
              />
            ))}
          </Tabs>

          {section === 'Summary' ? (
            <ReportSummary
              checks={checks}
              excludedNamespaces={excludedNamespaces}
              onOpenSection={nextSection => setSection(nextSection)}
            />
          ) : (
            <>
              <Stack direction={{ xs: 'column', md: 'row' }} spacing={1.5} flexWrap="wrap" alignItems={{ xs: 'stretch', md: 'center' }} justifyContent="space-between">
                <Typography variant="body2" color="text.secondary">
                  Showing {visibleChecks.length} of {sectionChecks.length} checks in {detailSection === 'All' ? 'all sections' : reportSectionLabel(detailSection)}
                </Typography>
                <CheckFilterBar
                  severity={severity}
                  severityCounts={severityCounts}
                  status={status}
                  statusCounts={statusCounts}
                  onClearAll={() => {
                    setStatus('all');
                    setSeverity('all');
                  }}
                  onSeverityChange={setSeverity}
                  onStatusChange={setStatus}
                />
              </Stack>
              <Stack spacing={2}>
                {visibleChecks.map(check => (
                  <CheckCard
                    check={check}
                    key={check.id}
                    returnFindingKey={returnTarget?.checkId === check.id ? returnTarget.findingKey : undefined}
                  />
                ))}
                {visibleChecks.length === 0 && (
                  <Alert severity="info">No checks match the selected filters.</Alert>
                )}
              </Stack>
            </>
          )}
        </>
      )}
    </Stack>
  );
}

function KubeBuddyDashboard() {
  const location = useLocation();
  const clusterKey = clusterKeyFromPath(location.pathname);
  const [storedReport, setStoredReport] = React.useState<StoredReport | null>(() => readStoredReport(clusterKey));
  const [config, setConfig] = React.useState<KubeBuddyConfig>(() => readKubeBuddyConfig(clusterKey));
  const [scanRun, setScanRun] = React.useState(0);
  const hasScan = Boolean(scanRun || storedReport);
  const reportExcludedNamespaces = storedReport?.config?.excludedNamespaces || storedReport?.excludedNamespaces || config.excludedNamespaces;
  const startScan = React.useCallback(() => {
    setStoredReport(null);
    setScanRun(run => run + 1);
  }, []);
  const prepareNewScan = React.useCallback(() => {
    setStoredReport(null);
    setScanRun(0);
  }, []);
  const handleScanComplete = React.useCallback((report: StoredReport) => {
    setStoredReport(report);
    setScanRun(0);
  }, []);
  const updateConfig = React.useCallback(
    (nextConfig: KubeBuddyConfig) => {
      const normalizedConfig = normalizeKubeBuddyConfig(nextConfig);

      setConfig(normalizedConfig);
      storeKubeBuddyConfig(clusterKey, normalizedConfig);

      if (
        storedReport &&
        JSON.stringify(normalizedConfig) !==
          JSON.stringify(normalizeKubeBuddyConfig(storedReport.config || {
            ...defaultKubeBuddyConfig(),
            excludedNamespaces: storedReport.excludedNamespaces || DEFAULT_EXCLUDED_NAMESPACES,
          }))
      ) {
        setStoredReport(null);
        setScanRun(0);
      }
    },
    [clusterKey, storedReport]
  );

  React.useEffect(() => {
    setStoredReport(readStoredReport(clusterKey));
    setConfig(readKubeBuddyConfig(clusterKey));
    setScanRun(0);
  }, [clusterKey]);

  return (
    <SectionBox title="KubeBuddy">
      <Stack spacing={2.5}>
        <Stack
          direction={{ xs: 'column', md: 'row' }}
          justifyContent="space-between"
          spacing={2}
          alignItems={{ xs: 'stretch', md: 'flex-start' }}
        >
          <Box>
            <Typography variant="body1">Check the health of this cluster with KubeBuddy.</Typography>
            <Typography variant="body2" color="text.secondary">
              Start a scan when you want a fresh score, findings, and recommendations from the resources Headlamp can already see.
            </Typography>
            <Link href="https://kubebuddy.io/cli/checks/" target="_blank" rel="noreferrer" variant="body2">
              View KubeBuddy check catalog
            </Link>
          </Box>
          {hasScan && (
            <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} sx={{ alignSelf: { xs: 'stretch', md: 'flex-start' } }}>
              {storedReport && !scanRun && (
                <Button
                  variant="outlined"
                  onClick={() => exportReportCsv(clusterKey, storedReport)}
                  sx={{ whiteSpace: 'nowrap' }}
                >
                  Export CSV
                </Button>
              )}
              <Button
                variant="contained"
                onClick={storedReport && !scanRun ? prepareNewScan : startScan}
                sx={{ whiteSpace: 'nowrap' }}
              >
                {storedReport && !scanRun ? 'Configure New Scan' : 'Run Scan Again'}
              </Button>
            </Stack>
          )}
        </Stack>

        {!storedReport && !scanRun && (
          <NamespaceExclusionsControl config={config} onChange={updateConfig} />
        )}

        {hasScan ? (
          <KubeBuddyScanResults
            clusterKey={clusterKey}
            config={config}
            excludedNamespaces={reportExcludedNamespaces}
            initialReport={scanRun ? null : storedReport}
            key={scanRun || `stored-${storedReport?.completedAt}`}
            onScanComplete={handleScanComplete}
          />
        ) : (
          <ReadyToScanState onStart={startScan} />
        )}
      </Stack>
    </SectionBox>
  );
}

function KubeBuddyConfigPage() {
  const location = useLocation();
  const clusterKey = clusterKeyFromPath(location.pathname);
  const [config, setConfig] = React.useState<KubeBuddyConfig>(() => readKubeBuddyConfig(clusterKey));

  const updateConfig = React.useCallback(
    (nextConfig: KubeBuddyConfig) => {
      const normalizedConfig = normalizeKubeBuddyConfig(nextConfig);
      setConfig(normalizedConfig);
      storeKubeBuddyConfig(clusterKey, normalizedConfig);
    },
    [clusterKey]
  );

  React.useEffect(() => {
    setConfig(readKubeBuddyConfig(clusterKey));
  }, [clusterKey]);

  return (
    <SectionBox title="KubeBuddy Config">
      <Stack spacing={2.5}>
        <Box>
          <Typography variant="body1">Configure KubeBuddy scan behavior for this Headlamp cluster.</Typography>
          <Typography variant="body2" color="text.secondary">
            Namespace exclusions stay on the scan page. These settings cover trusted registries and thresholds.
          </Typography>
          <Link href="https://kubebuddy.io/cli/checks/" target="_blank" rel="noreferrer" variant="body2">
            View KubeBuddy check catalog
          </Link>
        </Box>
        <KubeBuddyAdvancedConfigControl config={config} onChange={updateConfig} />
      </Stack>
    </SectionBox>
  );
}

registerAppBarAction(<KubeBuddyScoreBadge />);

registerSidebarEntry({
  parent: null,
  name: 'kubebuddy',
  label: 'KubeBuddy',
  url: '/kubebuddy',
  icon: KUBEBUDDY_ICON,
});

registerSidebarEntry({
  parent: 'kubebuddy',
  name: 'kubebuddy-config',
  label: 'Config',
  url: '/kubebuddy/config',
});

registerSidebarEntry({
  parent: 'kubebuddy',
  name: 'kubebuddy-scan',
  label: 'Scan',
  url: '/kubebuddy',
});

registerRoute({
  path: '/kubebuddy',
  sidebar: 'kubebuddy-scan',
  name: 'kubebuddy',
  exact: true,
  component: KubeBuddyDashboard,
});

registerRoute({
  path: '/kubebuddy/config',
  sidebar: 'kubebuddy-config',
  name: 'kubebuddy-config',
  exact: true,
  component: KubeBuddyConfigPage,
});
