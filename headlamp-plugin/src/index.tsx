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
import { makeCustomResourceClass } from '@kinvolk/headlamp-plugin/lib/lib/k8s/crd';
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
  Menu,
  MenuItem,
  Paper,
  Stack,
  SvgIcon,
  Tab,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TablePagination,
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
import YAML from 'yaml';
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
  message?: string;
  link?: string;
  yamlPath?: string;
  yamlSnippet?: string;
  sourceAnnotations?: Record<string, unknown>;
};

type FindingOptions = {
  yamlPath?: string;
  yamlValue?: unknown;
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
  suppressedFindings?: SuppressedFinding[];
};

type SuppressedFinding = Finding & {
  suppressionReason?: string;
  suppressionUntil?: string;
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
  rawYaml?: string;
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
const SCORE_FRESH_MS = 24 * 60 * 60 * 1000;
const SCORE_HISTORY_LIMIT = 30;
const CHECKS_PER_SCAN_STEP = 2;
const SCAN_STEP_DELAY_MS = 25;
const IGNORE_CHECKS_ANNOTATION = 'kubebuddy.io/ignore-checks';
const IGNORE_REASON_ANNOTATION = 'kubebuddy.io/ignore-reason';
const IGNORE_UNTIL_ANNOTATION = 'kubebuddy.io/ignore-until';
const EventResource = makeCustomResourceClass({
  apiInfo: [
    { group: '', version: 'v1' },
    { group: 'events.k8s.io', version: 'v1' },
  ],
  kind: 'Event',
  pluralName: 'events',
  singularName: 'event',
  isNamespaced: true,
});
const MutatingWebhookConfiguration = makeCustomResourceClass({
  apiInfo: [
    { group: 'admissionregistration.k8s.io', version: 'v1' },
    { group: 'admissionregistration.k8s.io', version: 'v1beta1' },
  ],
  kind: 'MutatingWebhookConfiguration',
  pluralName: 'mutatingwebhookconfigurations',
  singularName: 'mutatingwebhookconfiguration',
  isNamespaced: false,
});
const ValidatingAdmissionPolicy = makeCustomResourceClass({
  apiInfo: [
    { group: 'admissionregistration.k8s.io', version: 'v1' },
    { group: 'admissionregistration.k8s.io', version: 'v1beta1' },
  ],
  kind: 'ValidatingAdmissionPolicy',
  pluralName: 'validatingadmissionpolicies',
  singularName: 'validatingadmissionpolicy',
  isNamespaced: false,
});
const ValidatingWebhookConfiguration = makeCustomResourceClass({
  apiInfo: [
    { group: 'admissionregistration.k8s.io', version: 'v1' },
    { group: 'admissionregistration.k8s.io', version: 'v1beta1' },
  ],
  kind: 'ValidatingWebhookConfiguration',
  pluralName: 'validatingwebhookconfigurations',
  singularName: 'validatingwebhookconfiguration',
  isNamespaced: false,
});
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

type StoredScoreHistoryPoint = StoredScore & {
  passed: number;
  skipped: number;
  findings: number;
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

function scoreHistoryStorageKey(clusterKey: string): string {
  return `kubebuddy:score-history:${clusterKey}`;
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

function configYamlStorageKey(clusterKey: string): string {
  return `kubebuddy:config-yaml:${clusterKey}`;
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
  const trustedRegistries = Array.isArray(config.trustedRegistries)
    ? normalizeRegistries(config.trustedRegistries)
    : defaults.trustedRegistries;
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
    trustedRegistries: trustedRegistries.length > 0 ? trustedRegistries : defaults.trustedRegistries,
    rawYaml: typeof config.rawYaml === 'string' ? config.rawYaml : undefined,
    thresholds: {
      ...defaults.thresholds,
      ...(config.thresholds || {}),
    },
  };

  return normalized;
}

function cliYamlToConfig(rawYaml: string): KubeBuddyConfig {
  const parsed = YAML.parse(rawYaml) || {};
  const thresholds = parsed.thresholds || {};

  return normalizeKubeBuddyConfig({
    excludedNamespaces: Array.isArray(parsed.excluded_namespaces)
      ? parsed.excluded_namespaces.map(String)
      : undefined,
    excludedChecks: Array.isArray(parsed.excluded_checks)
      ? parsed.excluded_checks.map(String)
      : undefined,
    trustedRegistries: Array.isArray(parsed.trusted_registries)
      ? parsed.trusted_registries.map(String)
      : undefined,
    rawYaml,
    thresholds: {
      restartsWarning: Number(thresholds.restarts_warning) || DEFAULT_THRESHOLDS.restartsWarning,
      restartsCritical: Number(thresholds.restarts_critical) || DEFAULT_THRESHOLDS.restartsCritical,
      podAgeWarning: Number(thresholds.pod_age_warning) || DEFAULT_THRESHOLDS.podAgeWarning,
      stuckJobHours: Number(thresholds.stuck_job_hours) || DEFAULT_THRESHOLDS.stuckJobHours,
      podsPerNodeCritical: Number(thresholds.pods_per_node_critical) || DEFAULT_THRESHOLDS.podsPerNodeCritical,
    },
  });
}

function configToCliYaml(config: KubeBuddyConfig): string {
  const normalized = normalizeKubeBuddyConfig(config);
  const parsed = normalized.rawYaml ? YAML.parse(normalized.rawYaml) || {} : {};

  parsed.thresholds = {
    ...(parsed.thresholds || {}),
    restarts_warning: normalized.thresholds.restartsWarning,
    restarts_critical: normalized.thresholds.restartsCritical,
    pod_age_warning: normalized.thresholds.podAgeWarning,
    stuck_job_hours: normalized.thresholds.stuckJobHours,
    pods_per_node_critical: normalized.thresholds.podsPerNodeCritical,
  };
  parsed.excluded_namespaces = normalized.excludedNamespaces;
  parsed.trusted_registries = normalized.trustedRegistries;
  parsed.excluded_checks = normalized.excludedChecks;

  if (!parsed.radar) {
    parsed.radar = {
      enabled: false,
      api_base_url: 'https://radar.kubebuddy.io/api/kb-radar/v1',
      environment: 'prod',
      api_user_env: 'KUBEBUDDY_RADAR_API_USER',
      api_password_env: 'KUBEBUDDY_RADAR_API_PASSWORD',
      upload_timeout_seconds: 30,
      upload_retries: 2,
    };
  }

  return YAML.stringify(parsed);
}

function readKubeBuddyConfig(clusterKey: string): KubeBuddyConfig {
  const defaults = defaultKubeBuddyConfig();
  const rawYaml = window.localStorage.getItem(configYamlStorageKey(clusterKey)) || undefined;

  try {
    const value = window.localStorage.getItem(configStorageKey(clusterKey));
    if (!value) {
      return normalizeKubeBuddyConfig({
        ...defaults,
        excludedNamespaces: readExcludedNamespaces(clusterKey),
        rawYaml,
      });
    }

    const parsed = JSON.parse(value) as Partial<KubeBuddyConfig>;
    return normalizeKubeBuddyConfig({ ...parsed, rawYaml: parsed.rawYaml || rawYaml });
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

  const rawYaml = configToCliYaml(normalized);
  const stored = { ...normalized, rawYaml };

  window.localStorage.setItem(configStorageKey(clusterKey), JSON.stringify(stored));
  window.localStorage.setItem(configYamlStorageKey(clusterKey), rawYaml);
  storeExcludedNamespaces(clusterKey, stored.excludedNamespaces);
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

function readStoredScoreHistory(clusterKey: string): StoredScoreHistoryPoint[] {
  try {
    const value = window.localStorage.getItem(scoreHistoryStorageKey(clusterKey));
    if (!value) {
      return [];
    }

    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed)) {
      return [];
    }

    return parsed
      .filter(point =>
        typeof point.value === 'number' &&
        typeof point.failed === 'number' &&
        typeof point.passed === 'number' &&
        typeof point.skipped === 'number' &&
        typeof point.total === 'number' &&
        typeof point.findings === 'number' &&
        typeof point.completedAt === 'string'
      )
      .slice(-SCORE_HISTORY_LIMIT) as StoredScoreHistoryPoint[];
  } catch {
    return [];
  }
}

function appendStoredScoreHistory(clusterKey: string, point: StoredScoreHistoryPoint): StoredScoreHistoryPoint[] {
  const history = [...readStoredScoreHistory(clusterKey), point].slice(-SCORE_HISTORY_LIMIT);

  window.localStorage.setItem(scoreHistoryStorageKey(clusterKey), JSON.stringify(history));

  return history;
}

function storeScore(clusterKey: string, checks: CheckResult[], completedAt = new Date().toISOString()): StoredScore {
  const score = scoreChecks(checks);
  const findings = checks.reduce((total, check) => total + check.findings.length, 0);
  const storedScore: StoredScore = {
    value: score.value,
    failed: score.failed,
    total: score.total,
    completedAt,
  };

  window.localStorage.setItem(scoreStorageKey(clusterKey), JSON.stringify(storedScore));
  appendStoredScoreHistory(clusterKey, {
    ...storedScore,
    passed: score.passed,
    skipped: score.skipped,
    findings,
  });
  window.dispatchEvent(new CustomEvent(SCORE_UPDATED_EVENT, { detail: { clusterKey } }));

  return storedScore;
}

function storeReport(clusterKey: string, checks: CheckResult[], config: KubeBuddyConfig): StoredReport {
  const completedAt = new Date().toISOString();
  const storedReport: StoredReport = {
    checks,
    completedAt,
    excludedNamespaces: normalizeNamespaceList(config.excludedNamespaces),
    config,
  };

  window.localStorage.setItem(reportStorageKey(clusterKey), JSON.stringify(storedReport));
  storeScore(clusterKey, checks, completedAt);

  return storedReport;
}

function csvValue(value: unknown): string {
  const text = value === null || value === undefined ? '' : String(value);
  return `"${text.replace(/"/g, '""')}"`;
}

function downloadTextFile(filename: string, content: string, type: string): void {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');

  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function reportExportPrefix(clusterKey: string, completedAt: string): string {
  const safeCluster = clusterKey.replace(/[^a-z0-9_-]+/gi, '-').replace(/^-+|-+$/g, '') || 'cluster';
  const safeCompletedAt = completedAt.replace(/[:.]/g, '-');

  return `kubebuddy-${safeCluster}-${safeCompletedAt}`;
}

function exportReportJson(clusterKey: string, report: StoredReport): void {
  const payload = {
    cluster: clusterKey,
    completedAt: report.completedAt,
    score: scoreChecks(report.checks),
    excludedNamespaces: report.excludedNamespaces || [],
    config: report.config,
    checks: report.checks,
  };

  downloadTextFile(
    `${reportExportPrefix(clusterKey, report.completedAt)}.json`,
    JSON.stringify(payload, null, 2),
    'application/json;charset=utf-8'
  );
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
    'evidence',
    'message',
    'details',
    'yaml_path',
    'yaml_snippet',
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
        '',
        check.skippedReason || '',
        check.skippedReason || '',
        '',
        '',
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
      evidenceLabel(finding),
      findingMessage(check, finding),
      finding.details,
      finding.yamlPath || '',
      finding.yamlSnippet || '',
      check.recommendation,
      check.docs || '',
    ]);
  });

  const csv = [
    headers.map(csvValue).join(','),
    ...rows.map(row => row.map(csvValue).join(',')),
  ].join('\r\n');

  downloadTextFile(`${reportExportPrefix(clusterKey, report.completedAt)}.csv`, csv, 'text/csv;charset=utf-8');
}

function ReportExportButton({ clusterKey, report }: { clusterKey: string; report: StoredReport }) {
  const [anchorEl, setAnchorEl] = React.useState<HTMLElement | null>(null);
  const open = Boolean(anchorEl);
  const closeMenu = () => setAnchorEl(null);
  const exportJson = () => {
    exportReportJson(clusterKey, report);
    closeMenu();
  };
  const exportCsv = () => {
    exportReportCsv(clusterKey, report);
    closeMenu();
  };

  return (
    <>
      <Button
        aria-controls={open ? 'kubebuddy-export-menu' : undefined}
        aria-expanded={open ? 'true' : undefined}
        aria-haspopup="menu"
        onClick={event => setAnchorEl(event.currentTarget)}
        sx={{ whiteSpace: 'nowrap' }}
        variant="outlined"
      >
        Export
      </Button>
      <Menu
        anchorEl={anchorEl}
        id="kubebuddy-export-menu"
        onClose={closeMenu}
        open={open}
      >
        <MenuItem onClick={exportJson}>JSON report</MenuItem>
        <MenuItem onClick={exportCsv}>CSV findings</MenuItem>
      </Menu>
    </>
  );
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
  return ['Gateways', 'HTTPRoutes', 'ValidatingAdmissionPolicies'].includes(label) && errorStatus(error) === '404';
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

  const suppressed = result.suppressedFindings?.length || 0;
  const suffix = suppressed > 0 ? `, ${suppressed} suppressed` : '';
  return `${result.id} checked - ${result.findings.length} finding${result.findings.length === 1 ? '' : 's'}${suffix}.`;
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

function useOptionalResourceList<T>(resourceClass: any): ResourceState<T> {
  if (!resourceClass || typeof resourceClass.useList !== 'function') {
    return EMPTY_RESOURCE_STATE;
  }

  return useResourceList<T>(resourceClass.useList());
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

function pathSegments(path: string): string[] {
  return path.split('.').filter(Boolean);
}

function valueAtPath(value: any, path: string | undefined): unknown {
  if (!path) {
    return value;
  }

  return pathSegments(path).reduce((current, segment) => {
    if (current === null || current === undefined) {
      return undefined;
    }

    const key = segment.replace(/\[[^\]]+\]$/, '');
    return current?.[key];
  }, value);
}

function yamlSnippetFromPath(path: string, value: unknown): string {
  const snippet = pathSegments(path).reduceRight<unknown>((current, segment) => {
    const match = segment.match(/^([^\[]+)\[([^=\]]+)=([^\]]+)\]$/);
    if (match) {
      const [, listName, selectorKeyName, selectorValue] = match;
      return { [listName]: [{ [selectorKeyName]: selectorValue, ...(current as Record<string, unknown>) }] };
    }

    return { [segment]: current };
  }, value);

  return YAML.stringify(snippet).trim();
}

function expressionYamlPath(expression: GeneratedExpression | undefined): string | undefined {
  if (!expression) {
    return undefined;
  }

  if (expression.path) {
    return expression.path;
  }

  if (expression.exists) {
    return expression.exists;
  }

  if (expression.len) {
    return expressionYamlPath(expression.len);
  }

  if (expression.count_where?.path) {
    return expression.count_where.path;
  }

  if (expression.coalesce?.length) {
    return expression.coalesce.map(expressionYamlPath).find(Boolean);
  }

  return undefined;
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

function finding(resource: any, details: string, message?: string, options: FindingOptions = {}): Finding {
  const yamlPath = options.yamlPath;
  const yamlValue = yamlPath ? options.yamlValue ?? valueAtPath(json(resource), yamlPath) : undefined;
  const yamlSnippetValue = yamlValue === undefined ? '<missing>' : yamlValue;

  return {
    resource: name(resource),
    namespace: namespace(resource),
    kind: kind(resource),
    apiVersion: apiVersion(resource),
    uid: uid(resource),
    commandName: name(resource),
    commandNamespace: namespace(resource),
    details,
    message,
    link: link(resource),
    yamlPath,
    yamlSnippet: yamlPath ? yamlSnippetFromPath(yamlPath, yamlSnippetValue) : undefined,
    sourceAnnotations: objectAnnotations(resource),
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

function containersWithMissingSlots(pod: any): any[] {
  const spec = json(pod)?.spec || {};
  return ['containers', 'initContainers', 'ephemeralContainers'].flatMap(containerSet => {
    if (spec[containerSet] === undefined || spec[containerSet] === null) {
      return [{}];
    }
    return spec[containerSet] || [];
  });
}

function containerYamlOptions(pod: any, container: any, fieldPath: string, yamlValue = valueAtPath(container, fieldPath)): FindingOptions {
  const spec = json(pod)?.spec || {};
  const listName = (spec.ephemeralContainers || []).some((item: any) => item === container)
    ? 'ephemeralContainers'
    : (spec.initContainers || []).some((item: any) => item === container)
    ? 'initContainers'
    : 'containers';
  const yamlPath = `spec.${listName}[name=${container.name || 'unknown'}].${fieldPath}`;

  return {
    yamlPath,
    yamlValue,
  };
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

function endpointSliceHasReadyEndpoint(endpointSlice: any): boolean {
  return (json(endpointSlice)?.endpoints || []).some((endpoint: any) => endpoint?.conditions?.ready !== false);
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

function workloadAllContainers(workload: any): any[] {
  const spec = workloadTemplate(workload)?.spec || {};
  return [...(spec.containers || []), ...(spec.initContainers || [])];
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

function isInternalIP(value: string): boolean {
  const parts = value.trim().split('.').map(part => Number(part));
  if (parts.length !== 4 || parts.some(part => !Number.isInteger(part) || part < 0 || part > 255)) {
    return false;
  }

  const [first, second] = parts;
  return (
    first === 10 ||
    first === 127 ||
    first === 169 && second === 254 ||
    first === 172 && second >= 16 && second <= 31 ||
    first === 192 && second === 168 ||
    first === 100 && second >= 64 && second <= 127 ||
    first === 0
  );
}

function serviceTargetPortMatchesPods(targetPort: string, pods: any[]): boolean {
  return pods.some(pod =>
    containers(pod, false).some(container =>
      (container.ports || []).some((port: any) =>
        String(port.name || '') === targetPort || String(port.containerPort || '') === targetPort
      )
    )
  );
}

function runAsUserValue(value: unknown): { set: boolean; value: number } {
  if (value === undefined || value === null || value === '') {
    return { set: false, value: 0 };
  }

  const numericValue = Number(value);
  return { set: Number.isFinite(numericValue), value: numericValue };
}

function replicatedWorkloadMissingSpread(workload: any): boolean {
  const replicas = Number(json(workload)?.spec?.replicas || 1);
  if (replicas <= 1) {
    return false;
  }

  const podSpec = json(workload)?.spec?.template?.spec;
  if (!podSpec) {
    return false;
  }

  return !(
    (podSpec.affinity?.podAntiAffinity?.requiredDuringSchedulingIgnoredDuringExecution || []).length ||
    (podSpec.affinity?.podAntiAffinity?.preferredDuringSchedulingIgnoredDuringExecution || []).length ||
    (podSpec.topologySpreadConstraints || []).length
  );
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
  const earnedWeight = scoreableChecks.reduce((total, check) => {
    if (check.weight <= 0) {
      return total;
    }
    return total + check.weight / (check.findings.length + 1);
  }, 0);
  const failedWeight = Math.max(0, totalWeight - earnedWeight);
  const value = totalWeight === 0 ? 100 : Math.round((earnedWeight / totalWeight) * 100);

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

function suppressionIncludesCheck(raw: string, checkId: string): boolean {
  const normalizedCheckId = checkId.trim().toUpperCase();
  return raw
    .split(/[,\s;]+/)
    .map(token => token.trim().toUpperCase())
    .filter(Boolean)
    .some(token => token === '*' || token === normalizedCheckId);
}

function suppressionExpired(raw: string): boolean {
  const trimmed = raw.trim();
  if (!trimmed) {
    return false;
  }
  const parsed = Date.parse(trimmed);
  return Number.isFinite(parsed) && Date.now() > parsed;
}

function suppressesFinding(checkId: string, finding: Finding): { reason?: string; until?: string } | null {
  const annotations = finding.sourceAnnotations || {};
  const ignoredChecks = String(annotations[IGNORE_CHECKS_ANNOTATION] || '').trim();
  if (!ignoredChecks || !suppressionIncludesCheck(ignoredChecks, checkId)) {
    return null;
  }

  const until = String(annotations[IGNORE_UNTIL_ANNOTATION] || '').trim();
  if (until && suppressionExpired(until)) {
    return null;
  }

  return {
    reason: String(annotations[IGNORE_REASON_ANNOTATION] || '').trim(),
    until,
  };
}

function applyFindingSuppressions(checkId: string, findings: Finding[]): {
  findings: Finding[];
  suppressedFindings: SuppressedFinding[];
} {
  const active: Finding[] = [];
  const suppressedFindings: SuppressedFinding[] = [];
  const publicFinding = (finding: Finding): Finding => {
    const { sourceAnnotations, ...rest } = finding;
    return rest;
  };

  findings.forEach(finding => {
    const suppression = suppressesFinding(checkId, finding);
    if (!suppression) {
      active.push(publicFinding(finding));
      return;
    }

    suppressedFindings.push({
      ...publicFinding(finding),
      suppressionReason: suppression.reason,
      suppressionUntil: suppression.until,
    });
  });

  return { findings: active, suppressedFindings };
}

function resultFromCheck(
  check: GeneratedCheck,
  findings: Finding[],
  status?: CheckStatus,
  skippedReason?: string
): CheckResult {
  const suppression = applyFindingSuppressions(check.id, findings);
  const finalStatus = status || (suppression.findings.length > 0 ? 'failed' : 'passed');
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
    status: finalStatus,
    skippedReason,
    findings: suppression.findings,
    suppressedFindings: suppression.suppressedFindings,
  };
}

function emptyHandler(): Finding[] {
  return [];
}

function isSensitiveHostPath(path: string): boolean {
  const normalized = path.trim().toLowerCase().replace(/\\/g, '/').replace(/\/+$/, '');
  if (!normalized) {
    return false;
  }
  const exact = new Set([
    '/',
    '/etc',
    '/proc',
    '/sys',
    '/var/run/docker.sock',
    '/run/docker.sock',
    '/run/containerd/containerd.sock',
    '/var/run/containerd/containerd.sock',
  ]);
  return exact.has(normalized) || [
    '/etc/',
    '/proc/',
    '/sys/',
    '/var/lib/kubelet',
    '/var/lib/containerd',
    '/var/run/secrets',
  ].some(prefix => normalized.startsWith(prefix));
}

function podSecurityHandlers(resources: ResourceStates): Record<string, Finding[]> {
  const pods = resources.pod.data;
  return {
    SEC002: pods.filter(pod => json(pod)?.spec?.hostPID || json(pod)?.spec?.hostNetwork).map(pod => {
      const yamlPath = json(pod)?.spec?.hostPID ? 'spec.hostPID' : 'spec.hostNetwork';
      return finding(pod, 'hostPID or hostNetwork enabled', 'hostPID or hostNetwork enabled', { yamlPath });
    }),
    SEC003: pods.flatMap(pod => {
      const podUser = runAsUserValue(json(pod)?.spec?.securityContext?.runAsUser);
      return containersWithMissingSlots(pod).flatMap(container => {
        const containerUser = runAsUserValue(container?.securityContext?.runAsUser);
        const runsAsRoot =
          (containerUser.set && containerUser.value === 0) ||
          (!containerUser.set && podUser.set && podUser.value === 0) ||
          (!containerUser.set && !podUser.set);

        if (!runsAsRoot) {
          return [];
        }

        const options = containerUser.set
          ? containerYamlOptions(pod, container, 'securityContext.runAsUser')
          : podUser.set
            ? { yamlPath: 'spec.securityContext.runAsUser', yamlValue: podUser.value }
            : containerYamlOptions(pod, container, 'securityContext', container.securityContext || {});
        return [finding(pod, `Container ${container.name} runs as root or has no runAsUser set`, `Container ${container.name} runs as root or has no runAsUser set`, options)];
      });
    }),
    SEC004: pods.flatMap(pod => containers(pod).filter(container => container?.securityContext?.privileged).map(container => finding(
      pod,
      `Container ${container.name} is privileged`,
      `Container ${container.name} is privileged`,
      containerYamlOptions(pod, container, 'securityContext.privileged')
    ))),
    SEC005: pods.filter(pod => json(pod)?.spec?.hostIPC).map(pod => finding(pod, 'hostIPC enabled', 'hostIPC enabled', { yamlPath: 'spec.hostIPC' })),
    SEC006: pods.flatMap(pod => containers(pod, false).filter(container => {
      const context = container?.securityContext;
      return !context || context.runAsNonRoot !== true || context.readOnlyRootFilesystem !== true || context.allowPrivilegeEscalation !== false;
    }).map(container => finding(pod, `Container ${container.name} missing hardened securityContext`, `Container ${container.name} missing hardened securityContext`, containerYamlOptions(pod, container, 'securityContext', container.securityContext || {})))),
    SEC008: pods.flatMap(pod => containers(pod).flatMap(container => (container.env || []).filter((env: any) => env?.valueFrom?.secretKeyRef?.name).map((env: any) => finding(
      pod,
      `Secret exposed through env ${env.name} in ${container.name}`,
      `Secret exposed through env ${env.name} in ${container.name}`,
      containerYamlOptions(pod, container, `env[name=${env.name || 'unknown'}].valueFrom.secretKeyRef`, env.valueFrom.secretKeyRef)
    )))),
    SEC009: pods.flatMap(pod => containers(pod, false).filter(container => !(container?.securityContext?.capabilities?.drop || []).some((value: any) => String(value).toLowerCase() === 'all')).map(container => finding(pod, `Container ${container.name} does not drop ALL capabilities`, `Container ${container.name} does not drop ALL capabilities`, containerYamlOptions(pod, container, 'securityContext.capabilities.drop', container?.securityContext?.capabilities?.drop || [])))),
    SEC010: pods.flatMap(pod => (json(pod)?.spec?.volumes || []).filter((volume: any) => volume.hostPath?.path).map((volume: any) => finding(pod, `hostPath volume ${volume.name}: ${volume.hostPath.path}`, `hostPath volume ${volume.name}: ${volume.hostPath.path}`, { yamlPath: `spec.volumes[name=${volume.name || 'unknown'}].hostPath`, yamlValue: volume.hostPath }))),
    SEC011: pods.flatMap(pod => containers(pod, false).filter(container => Number(container?.securityContext?.runAsUser || 0) === 0).map(container => finding(pod, `Container ${container.name} runs as UID 0`, `Container ${container.name} runs as UID 0`, containerYamlOptions(pod, container, 'securityContext.runAsUser', container?.securityContext?.runAsUser || 0)))),
    SEC012: pods.flatMap(pod => containers(pod, false).filter(container => (container?.securityContext?.capabilities?.add || []).length > 0).map(container => finding(pod, `Container ${container.name} adds capabilities`, `Container ${container.name} adds capabilities`, containerYamlOptions(pod, container, 'securityContext.capabilities.add')))),
    SEC013: pods.flatMap(pod => (json(pod)?.spec?.volumes || []).filter((volume: any) => volume.emptyDir).map((volume: any) => finding(pod, `emptyDir volume ${volume.name}`, `emptyDir volume ${volume.name}`, { yamlPath: `spec.volumes[name=${volume.name || 'unknown'}].emptyDir`, yamlValue: volume.emptyDir }))),
    SEC016: pods.flatMap(pod => containers(pod).filter(container => container?.securityContext?.windowsOptions?.hostProcess).map(container => finding(pod, `Windows HostProcess container ${container.name}`, `Windows HostProcess container ${container.name}`, containerYamlOptions(pod, container, 'securityContext.windowsOptions.hostProcess')))),
    SEC017: pods.flatMap(pod => containers(pod).filter(container => container?.securityContext?.procMount === 'Unmasked').map(container => finding(pod, `Container ${container.name} uses Unmasked procMount`, `Container ${container.name} uses Unmasked procMount`, containerYamlOptions(pod, container, 'securityContext.procMount')))),
    SEC019: pods.flatMap(pod => [
      ...Object.entries(objectAnnotations(pod))
        .filter(([key, value]) => key.startsWith('container.apparmor.security.beta.kubernetes.io/') && !['runtime/default'].includes(String(value)) && !String(value).startsWith('localhost/'))
        .map(([key, value]) => finding(pod, `Unsupported AppArmor annotation value on ${key}: ${value}`)),
      ...[
        ...containers(pod),
        ...(json(pod)?.spec?.ephemeralContainers || []),
      ]
        .filter(container => {
          const profileType = stringValue(container?.securityContext?.appArmorProfile?.type);
          return profileType !== '' && profileType !== 'RuntimeDefault' && profileType !== 'Localhost';
        })
        .map(container => finding(pod, `Container ${container.name} uses unsupported AppArmor profile type ${container.securityContext.appArmorProfile.type}`)),
    ]),
    SEC020: pods.flatMap(pod => containers(pod).filter(container => !container?.securityContext?.seccompProfile?.type && !json(pod)?.spec?.securityContext?.seccompProfile?.type).map(container => finding(pod, `Container ${container.name} has no seccomp profile`, `Container ${container.name} has no seccomp profile`, containerYamlOptions(pod, container, 'securityContext.seccompProfile', container?.securityContext?.seccompProfile || {})))),
    SEC021: pods.flatMap(pod => containers(pod).flatMap(container => (container.ports || [])
      .filter((port: any) => Number(port.hostPort) > 0)
      .map((port: any) => finding(pod, `Container ${container.name} uses hostPort ${port.hostPort}`, `Container ${container.name} uses hostPort ${port.hostPort}`, containerYamlOptions(pod, container, 'ports', container.ports))))),
    SEC015: pods.filter(pod => serviceAccountName(pod) === 'default').map(pod => finding(pod, 'Uses default ServiceAccount', 'Uses default ServiceAccount', { yamlPath: 'spec.serviceAccountName', yamlValue: serviceAccountName(pod) })),
    SEC023: pods.flatMap(pod => (json(pod)?.spec?.securityContext?.sysctls || [])
      .filter((sysctl: any) => !['kernel.shm_rmid_forced', 'net.ipv4.ip_local_port_range', 'net.ipv4.ip_unprivileged_port_start', 'net.ipv4.tcp_syncookies', 'net.ipv4.ping_group_range'].includes(String(sysctl?.name || '')))
      .map((sysctl: any) => finding(pod, `Disallowed sysctl ${sysctl.name}`, `Disallowed sysctl ${sysctl.name}`, { yamlPath: 'spec.securityContext.sysctls', yamlValue: json(pod)?.spec?.securityContext?.sysctls }))),
    SEC027: pods.flatMap(pod => (json(pod)?.spec?.volumes || [])
      .filter((volume: any) => volume.gitRepo)
      .map((volume: any) => finding(pod, `gitRepo volume ${volume.name}: ${volume.gitRepo.repository || 'repository not set'}`, `gitRepo volume ${volume.name}`, { yamlPath: `spec.volumes[name=${volume.name || 'unknown'}].gitRepo`, yamlValue: volume.gitRepo }))),
    SEC029: pods.flatMap(pod => (json(pod)?.spec?.volumes || [])
      .filter((volume: any) => volume.hostPath?.path && isSensitiveHostPath(String(volume.hostPath.path)))
      .map((volume: any) => finding(
        pod,
        `hostPath volume ${volume.name}: ${volume.hostPath.path}`,
        `hostPath volume ${volume.name}: ${volume.hostPath.path}`,
        {
          yamlPath: `spec.volumes[name=${volume.name || 'unknown'}].hostPath.path`,
          yamlValue: volume.hostPath.path,
        }
      ))),
  };
}

function workloadResourceFindings(resources: ResourceStates, mode: 'requests' | 'limits', memoryOnly = false): Finding[] {
  const required: ('cpu' | 'memory')[] = memoryOnly ? ['memory'] : ['cpu', 'memory'];
  return allWorkloads(resources).flatMap(workload =>
    workloadAllContainers(workload).flatMap(container => {
      const missing = required.filter(resource => !hasResource(container, mode, resource));
      if (missing.length === 0) {
        return [];
      }

      const noun = mode === 'requests' ? 'request' : 'limit';
      return [finding(workload, `Container ${container.name} missing ${missing.map(resource => `${resource.toUpperCase()} ${noun}`).join(', ')}`)];
    })
  );
}

function workloadProbeFindings(resources: ResourceStates): Finding[] {
  return allWorkloads(resources).flatMap(workload =>
    workloadContainers(workload)
      .filter(container => !hasProbe(container))
      .map(container => finding(workload, `Container ${container.name} missing readiness or liveness probe`))
  );
}

function namespaceHasAny(resources: ResourceStates, namespaceName: string, kinds: string[]): boolean {
  return kinds.some(kind =>
    resources[kind].data.some(item => namespace(item) === namespaceName)
  );
}

function namespaceHygieneFindings(resources: ResourceStates): Finding[] {
  const trackedKinds = ['secret', 'persistentvolumeclaim', 'service', 'configmap', 'deployment', 'statefulset', 'daemonset'];

  return resources.namespace.data
    .filter(ns => !namespaceHasAny(resources, name(ns), ['pod']))
    .map(ns => finding(
      ns,
      namespaceHasAny(resources, name(ns), trackedKinds)
        ? 'No pods, but other resources exist'
        : 'Namespace has no workloads or tracked resources'
    ));
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
  const addSecret = (ns: string, secretName: string) => {
    if (!secretName) {
      return;
    }
    used.add(`${ns}/${secretName}`);
    used.add(`*/${secretName}`);
  };
  const addPodSpecSecretRefs = (podSpec: any, ns: string) => {
    (podSpec?.imagePullSecrets || []).forEach((secret: any) => addSecret(ns, secret.name));
    (podSpec?.volumes || []).forEach((volume: any) => addSecret(ns, volume.secret?.secretName));
    [...(podSpec?.containers || []), ...(podSpec?.initContainers || []), ...(podSpec?.ephemeralContainers || [])].forEach((container: any) => {
      (container.env || []).forEach((env: any) => addSecret(ns, env?.valueFrom?.secretKeyRef?.name));
      (container.envFrom || []).forEach((env: any) => addSecret(ns, env?.secretRef?.name));
    });
  };

  resources.pod.data.forEach(pod => {
    addPodSpecSecretRefs(json(pod)?.spec, namespace(pod) || 'default');
  });
  allWorkloads(resources).forEach(workload => {
    addPodSpecSecretRefs(workloadTemplate(workload)?.spec, namespace(workload) || 'default');
  });
  resources.ingress.data.forEach(ingress => {
    const ns = namespace(ingress) || 'default';
    (json(ingress)?.spec?.tls || []).forEach((tls: any) => addSecret(ns, tls.secretName));
  });
  resources.serviceaccount.data.forEach(sa => {
    const ns = namespace(sa) || 'default';
    (json(sa)?.secrets || []).forEach((secret: any) => addSecret(ns, secret.name));
  });
  return used;
}

function missingSecretReferenceFindings(resources: ResourceStates): Finding[] {
  const existing = new Set(resources.secret.data.map(secret => `${namespace(secret) || 'default'}/${name(secret)}`));
  const findings: Finding[] = [];

  resources.pod.data.forEach(pod => {
    const ns = namespace(pod) || 'default';
    const podName = name(pod);
    const missing = (secretName: string, detail: string) => {
      if (secretName && !existing.has(`${ns}/${secretName}`)) {
        findings.push(finding(pod, `${detail} references missing Secret ${secretName}`, `Pod ${podName} references missing Secret ${secretName}`));
      }
    };

    (json(pod)?.spec?.volumes || []).forEach((volume: any) => {
      if (volume.secret?.optional !== true) {
        missing(volume.secret?.secretName || '', `Volume ${volume.name || 'unknown'}`);
      }
    });
    containers(pod).forEach(container => {
      (container.env || []).forEach((env: any) => {
        if (env?.valueFrom?.secretKeyRef?.optional !== true) {
          missing(env?.valueFrom?.secretKeyRef?.name || '', `Container ${container.name} env ${env.name || 'unknown'}`);
        }
      });
      (container.envFrom || []).forEach((envFrom: any) => {
        if (envFrom?.secretRef?.optional !== true) {
          missing(envFrom?.secretRef?.name || '', `Container ${container.name} envFrom`);
        }
      });
    });
  });

  return findings;
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

function isKubernetesBootstrapClusterRole(role: any): boolean {
  const roleName = name(role);
  const labels = objectLabels(role);
  return (
    ['cluster-admin', 'admin', 'edit', 'view', 'system:public-info-viewer'].includes(roleName) ||
    roleName.startsWith('system:') ||
    roleName.startsWith('system:kube-') ||
    roleName.startsWith('system:node') ||
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

function isKubernetesDefaultRBACBinding(binding: any): boolean {
  const bindingName = name(binding);
  return (
    bindingName.startsWith('system:') ||
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

    if ((json(binding)?.subjects || []).length === 0) {
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
    if (isKubernetesBootstrapClusterRole(role)) {
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

function boundRoleRefsForRiskChecks(resources: ResourceStates, config: KubeBuddyConfig): Set<string> {
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
    if (isKubernetesDefaultRBACBinding(binding) || !bindingHasReportableRBACSubject(binding, '', config)) {
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

function recommendedLabelFindings(resource: any): Finding[] {
  const labels = objectLabels(resource);
  const templateLabels = workloadTemplate(resource)?.metadata?.labels || {};
  const required = [
    'app.kubernetes.io/name',
    'app.kubernetes.io/instance',
    'app.kubernetes.io/version',
    'app.kubernetes.io/component',
    'app.kubernetes.io/part-of',
    'app.kubernetes.io/managed-by',
  ];
  const missing = required.filter(label => labels[label] === undefined && templateLabels[label] === undefined);
  return missing.length > 0 ? [finding(resource, `Missing labels: ${missing.join(', ')}`)] : [];
}

function dangerousRBACReasons(rule: any): string[] {
  const reasons = new Set<string>();
  const verbs = rule?.verbs || [];
  const resources = rule?.resources || [];
  ['impersonate', 'bind', 'escalate'].forEach(verb => {
    if (verbs.includes(verb)) reasons.add(verb);
  });
  ['pods/exec', 'pods/portforward'].forEach(resource => {
    if (resources.includes(resource)) reasons.add(resource);
  });
  if (resources.includes('secrets') && ['*', 'get', 'list', 'watch'].some(verb => verbs.includes(verb))) {
    reasons.add('secret read');
  }
  return [...reasons];
}

function dangerousRBACFindings(role: any): Finding[] {
  if (isBuiltInClusterRole(role)) {
    return [];
  }

  return (json(role)?.rules || []).flatMap((rule: any) => {
    const reasons = dangerousRBACReasons(rule);
    return reasons.length > 0 ? [finding(role, `Dangerous RBAC access: ${reasons.join(', ')}`)] : [];
  });
}

function isControlledPod(pod: any): boolean {
  return (json(pod)?.metadata?.ownerReferences || []).length > 0;
}

function isStaticMirrorPod(pod: any): boolean {
  const annotations = objectAnnotations(pod);
  return !!annotations['kubernetes.io/config.mirror'] || !!annotations['kubernetes.io/config.source'];
}

function cronJobHygieneIssues(cronJob: any): string[] {
  const spec = json(cronJob)?.spec || {};
  const issues: string[] = [];
  if (!spec.concurrencyPolicy) issues.push('missing concurrencyPolicy');
  if (spec.startingDeadlineSeconds === undefined || spec.startingDeadlineSeconds === null) issues.push('missing startingDeadlineSeconds');
  if (spec.successfulJobsHistoryLimit === 0) issues.push('successfulJobsHistoryLimit is zero');
  if (spec.failedJobsHistoryLimit === 0) issues.push('failedJobsHistoryLimit is zero');
  if (spec.suspend === true) issues.push('suspended');
  return issues;
}

function includesString(values: unknown, expected: string): boolean {
  return toArray(values).some(value => String(value) === expected);
}

function stringValue(value: unknown): string {
  if (value === undefined || value === null) {
    return '';
  }
  return String(value).trim();
}

function selectorOverlaps(selector: unknown, labels: unknown): boolean {
  if (!selector || !labels || typeof selector !== 'object' || typeof labels !== 'object') {
    return false;
  }

  return Object.entries(selector as Record<string, unknown>).some(
    ([key, value]) => String((labels as Record<string, unknown>)[key]) === String(value)
  );
}

function weakPdbMessage(pdb: any): string {
  const spec = json(pdb)?.spec || {};
  const minAvailable = stringValue(spec.minAvailable);
  const maxUnavailable = stringValue(spec.maxUnavailable);

  if (minAvailable !== '' && Number(minAvailable) === 0) {
    return 'minAvailable = 0';
  }
  if (maxUnavailable === '1' || maxUnavailable === '100%') {
    return 'maxUnavailable = 100%';
  }
  return '';
}

function pdbCoverageFindings(resources: ResourceStates): Finding[] {
  const findings: Finding[] = [];
  const pdbNamespaces = new Set<string>();

  resources.poddisruptionbudget.data.forEach(pdb => {
    pdbNamespaces.add(namespace(pdb) || 'default');

    if (Number(json(pdb)?.status?.expectedPods || 0) === 0) {
      findings.push(finding(pdb, 'Matches 0 pods'));
    }

    const weak = weakPdbMessage(pdb);
    if (weak) {
      findings.push(finding(pdb, weak));
    }
  });

  [...resources.deployment.data, ...resources.statefulset.data].forEach(workload => {
    const workloadNamespace = namespace(workload) || 'default';
    if (!pdbNamespaces.has(workloadNamespace)) {
      return;
    }

    const labels = workloadLabels(workload);
    if (!labels || typeof labels !== 'object') {
      return;
    }

    const matched = resources.poddisruptionbudget.data.some(
      pdb =>
        (namespace(pdb) || 'default') === workloadNamespace &&
        selectorMatches(json(pdb)?.spec?.selector?.matchLabels, labels)
    );
    if (!matched) {
      findings.push(finding(workload, 'No matching PDB'));
    }
  });

  return findings;
}

function networkPolicyPermissiveFindings(resources: ResourceStates): Finding[] {
  return resources.networkpolicy.data.flatMap(policy => {
    const spec = json(policy)?.spec || {};
    const policyTypes = toArray(spec.policyTypes);
    const parts: string[] = [];

    if (includesString(policyTypes, 'Ingress') && toArray(spec.ingress).length === 0) {
      parts.push('Allows all Ingress traffic (empty ingress rules).');
    }
    if (includesString(policyTypes, 'Egress') && toArray(spec.egress).length === 0) {
      parts.push('Allows all Egress traffic (empty egress rules).');
    }
    toArray(spec.ingress).forEach((rule: any) => {
      toArray(rule?.from).forEach((from: any) => {
        if (from?.ipBlock?.cidr === '0.0.0.0/0') {
          parts.push("Ingress rule contains '0.0.0.0/0' ipBlock.");
        }
      });
    });
    toArray(spec.egress).forEach((rule: any) => {
      toArray(rule?.to).forEach((to: any) => {
        if (to?.ipBlock?.cidr === '0.0.0.0/0') {
          parts.push("Egress rule contains '0.0.0.0/0' ipBlock.");
        }
      });
    });

    return parts.length > 0 ? [finding(policy, parts.join(' '))] : [];
  });
}

function allocatedDeviceHealthFindings(resources: ResourceStates): Finding[] {
  return resources.pod.data.flatMap(pod => {
    const signals: string[] = [];

    ['containerStatuses', 'initContainerStatuses'].forEach(statusList => {
      toArray(json(pod)?.status?.[statusList]).forEach((containerStatus: any) => {
        const containerName = stringValue(containerStatus?.name);
        toArray(containerStatus?.allocatedResourcesStatus).forEach((resourceStatus: any) => {
          toArray(resourceStatus?.resources).forEach((health: any) => {
            const state = stringValue(health?.health);
            if (state !== 'Unhealthy' && state !== 'Unknown') {
              return;
            }
            const resourceName = stringValue(resourceStatus?.name || health?.resourceName || health?.resourceID);
            signals.push(`${containerName} ${resourceName} ${state}`.trim());
          });
        });
      });
    });

    return signals.length > 0
      ? [finding(pod, [...new Set(signals)].sort().join('; '), 'Pod has allocated device resources reporting Unhealthy or Unknown.')]
      : [];
  });
}

function webhookHasBroadScope(webhook: any): boolean {
  const hasNamespaceSelector = webhook?.namespaceSelector !== undefined && webhook?.namespaceSelector !== null;
  return toArray(webhook?.rules).some(
    (rule: any) =>
      includesString(rule?.resources, '*') &&
      includesString(rule?.operations, '*') &&
      !hasNamespaceSelector
  );
}

function admissionWebhookFindings(resources: ResourceStates): Finding[] {
  return [
    ...resources.mutatingwebhookconfiguration.data,
    ...resources.validatingwebhookconfiguration.data,
  ].flatMap(config => {
    const configName = name(config);

    return toArray(json(config)?.webhooks).flatMap((webhook: any) => {
      const issues: string[] = [];
      if (String(webhook?.failurePolicy || '').toLowerCase() === 'ignore') {
        issues.push('failurePolicy=Ignore');
      }
      if (!['None', 'NoneOnDryRun'].includes(stringValue(webhook?.sideEffects))) {
        issues.push('sideEffects not None/NoneOnDryRun');
      }
      if (webhookHasBroadScope(webhook)) {
        issues.push('broad wildcard scope');
      }

      return issues.length > 0
        ? [{
            resource: `admissionwebhook/${configName}`,
            namespace: '(cluster)',
            kind: kind(config),
            apiVersion: apiVersion(config),
            uid: uid(config),
            commandName: configName,
            details: issues.join(', '),
            message: `Webhook ${stringValue(webhook?.name) || 'unknown'} may fail open or apply too broadly`,
            link: link(config),
          }]
        : [];
    });
  });
}

function deploymentLabelConsistencyFindings(resources: ResourceStates): Finding[] {
  return resources.deployment.data.flatMap(deployment => {
    const selector = workloadSelector(deployment);
    const templateLabels = workloadLabels(deployment);
    const findings: Finding[] = [];

    if (!selectorMatches(selector, templateLabels)) {
      findings.push(finding(deployment, 'Deployment selector does not match pod template labels'));
    }

    resources.service.data.forEach(service => {
      const selector = serviceSelector(service);
      if (namespace(service) !== namespace(deployment) || !selector) {
        return;
      }
      if (selectorMatches(selector, templateLabels)) {
        return;
      }
      if (selectorOverlaps(selector, templateLabels)) {
        findings.push(finding(deployment, `Service selector does not align with deployment pod labels: service/${name(service)}`));
      }
    });

    return findings;
  });
}

function warningEventFindings(resources: ResourceStates): Finding[] {
  const grouped = new Map<string, { event: any; count: number }>();

  resources.events.data
    .filter(event => json(event)?.type === 'Warning')
    .forEach(event => {
      const eventData = json(event);
      const reason = stringValue(eventData?.reason);
      const message = stringValue(eventData?.message || eventData?.note);
      const key = `${reason}|${message}`;
      const existing = grouped.get(key);
      grouped.set(key, { event, count: (existing?.count || 0) + 1 });
    });

  return [...grouped.values()].map(({ event, count }) => {
    const eventData = json(event);
    const reason = stringValue(eventData?.reason) || 'Warning event';
    const message = stringValue(eventData?.message || eventData?.note) || reason;
    return finding(event, count > 1 ? `${count} events: ${reason} - ${message}` : message);
  });
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
    return [...byName.entries()]
      .filter(([, namespaces]) => namespaces.length > 1)
      .flatMap(([cmName, namespaces]) => namespaces.map(configMapNamespace => ({
        namespace: configMapNamespace,
        resource: `configmap/${cmName}`,
        details: `Found in namespaces: ${namespaces.join(', ')}`,
      })));
  },
  CFG003: resources => resources.configmap.data.filter(cm => JSON.stringify(json(cm)?.data || {}).length > 1048576).map(cm => finding(cm, 'ConfigMap exceeds 1 MiB')),
  EVENT001: warningEventFindings,
  EVENT002: resources => resources.events.data.filter(event => json(event)?.type === 'Warning').map(event => finding(event, json(event)?.reason || json(event)?.note || 'Warning event')),
  SEC014: (resources, config) => resources.pod.data.flatMap(pod =>
    containers(pod, false)
      .filter(container => !config.trustedRegistries.some(registry => String(container.image || '').startsWith(registry)))
      .map(container => finding(pod, `Image from untrusted registry: ${container.image}`))
  ),
  JOB001: (resources, config) => resources.job.data.filter(job => daysSince(json(job)?.status?.startTime) !== null && (Date.now() - new Date(json(job)?.status?.startTime).getTime()) > config.thresholds.stuckJobHours * 60 * 60 * 1000 && !json(job)?.status?.succeeded).map(job => finding(job, `Job running longer than ${config.thresholds.stuckJobHours} hours`)),
  JOB002: resources => resources.job.data.filter(job => (json(job)?.status?.failed || 0) > 0 && !json(job)?.status?.succeeded).map(job => finding(job, `${json(job)?.status?.failed} failures`)),
  JOB003: resources => resources.cronjob.data.flatMap(cronJob => {
    const issues = cronJobHygieneIssues(cronJob);
    return issues.length > 0 ? [finding(cronJob, issues.join(', '))] : [];
  }),
  NET001: resources => resources.service.data.filter(service => json(service)?.spec?.type !== 'ExternalName' && !resources.endpoints.data.some(ep => namespace(ep) === namespace(service) && name(ep) === name(service) && (json(ep)?.subsets || []).length > 0) && !resources.endpointslice.data.some(ep => namespace(ep) === namespace(service) && json(ep)?.metadata?.labels?.['kubernetes.io/service-name'] === name(service) && endpointSliceHasReadyEndpoint(ep))).map(service => finding(service, 'No endpoints or endpoint slices')),
  NET002: resources => resources.service.data.flatMap(service => {
    const serviceType = json(service)?.spec?.type;
    if (serviceType !== 'LoadBalancer' && serviceType !== 'NodePort') {
      return [];
    }

    const external = (json(service)?.status?.loadBalancer?.ingress || [])
      .map((entry: any) => String(entry?.ip || entry?.hostname || '').trim())
      .filter((value: string) => value && !isInternalIP(value));
    if (serviceType !== 'NodePort' && external.length === 0) {
      return [];
    }

    return [finding(service, external.length > 0 ? `Exposed via external IP: ${external.join(', ')}` : 'Exposed via NodePort')];
  }),
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
  NET007: resources => resources.service.data.flatMap(service => {
    if (json(service)?.spec?.type === 'ExternalName' || !serviceSelector(service)) {
      return [];
    }

    const matchingPods = resources.pod.data.filter(pod =>
      namespace(pod) === namespace(service) &&
      selectorMatches(serviceSelector(service), objectLabels(pod)) &&
      json(pod)?.status?.phase === 'Running'
    );
    if (matchingPods.length === 0) {
      return [];
    }

    return (json(service)?.spec?.ports || []).flatMap((port: any) => {
      const targetPort = String(port.targetPort || port.port || '').trim();
      return targetPort && !serviceTargetPortMatchesPods(targetPort, matchingPods)
        ? [finding(service, `Service targetPort '${targetPort}' not found in backing pods`)]
        : [];
    });
  }),
  NET008: resources => resources.service.data.filter(service => json(service)?.spec?.type === 'ExternalName' && /^\d+\.\d+\.\d+\.\d+$/.test(json(service)?.spec?.externalName || '')).map(service => finding(service, `ExternalName points to IP ${json(service)?.spec?.externalName}`)),
  NET009: networkPolicyPermissiveFindings,
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
  NET019: resources => resources.service.data.filter(service => {
    const externalIPs = json(service)?.spec?.externalIPs;
    return Array.isArray(externalIPs) && externalIPs.length > 0;
  }).map(service => finding(service, `externalIPs: ${json(service)?.spec?.externalIPs.join(', ')}`)),
  NET020: resources => [...resources.deployment.data, ...resources.daemonset.data, ...resources.statefulset.data, ...resources.pod.data, ...resources.service.data].filter(item => /ingress-nginx/i.test(JSON.stringify(json(item)))).map(item => finding(item, 'Ingress NGINX detected')),
  NODE001: resources => resources.node.data.filter(item => !nodeReady(item)).map(item => finding(item, 'Ready condition is not True')),
  NODE002: emptyHandler,
  NODE003: (resources, config) => resources.node.data.filter(node => Number(json(node)?.status?.capacity?.pods || 0) > 0 && resources.pod.data.filter(pod => json(pod)?.spec?.nodeName === name(node)).length / Number(json(node)?.status?.capacity?.pods || 1) > config.thresholds.podsPerNodeCritical / 100).map(node => finding(node, `Pod capacity above ${config.thresholds.podsPerNodeCritical}%`)),
  NS001: namespaceHygieneFindings,
  NS002: resources => resources.namespace.data.filter(ns => !resources.resourcequota.data.some(quota => namespace(quota) === name(ns))).map(ns => finding(ns, 'No ResourceQuota')),
  NS003: resources => resources.namespace.data.filter(ns => !resources.limitrange.data.some(limit => namespace(limit) === name(ns))).map(ns => finding(ns, 'No LimitRange')),
  NS004: resources => resources.pod.data.filter(pod => namespace(pod) === 'default').map(pod => finding(pod, 'Pod running in default namespace')),
  POD001: (resources, config) => resources.pod.data.map(pod => ({ pod, restarts: restartCount(pod) })).filter(item => item.restarts > config.thresholds.restartsWarning).map(item => finding(item.pod, `${item.restarts} restarts`)),
  POD002: (resources, config) => resources.pod.data.map(pod => ({ pod, age: daysSince(json(pod)?.status?.startTime) })).filter(item => json(item.pod)?.status?.phase === 'Running' && item.age !== null && item.age > config.thresholds.podAgeWarning).map(item => finding(item.pod, `${item.age} days old`)),
  POD006: resources => resources.pod.data.filter(pod => /debugger/i.test(name(pod))).map(pod => finding(pod, json(pod)?.status?.phase || 'Debug pod left behind')),
  POD007: resources => resources.pod.data.filter(pod => podImages(pod).some(image => !image.includes('@sha256:') && (image.endsWith(':latest') || image.lastIndexOf(':') <= image.lastIndexOf('/')))).map(pod => finding(pod, podImages(pod).join(', '))),
  POD008: resources => resources.pod.data.filter(pod => json(pod)?.spec?.automountServiceAccountToken !== false).map(pod => finding(pod, 'automountServiceAccountToken is enabled or inherited')),
  POD009: allocatedDeviceHealthFindings,
  POD010: resources => resources.pod.data.filter(pod => !isStaticMirrorPod(pod) && !isControlledPod(pod)).map(pod => finding(pod, 'Pod is not managed by a workload controller')),
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
        .filter(role => bound.has(`ClusterRole:${name(role)}`) && grantsKubeletProxy(role))
        .map(role => finding(role, 'Grants nodes/proxy access')),
      ...resources.role.data
        .filter(role => bound.has(`Role:${rbacResourceKey(role)}`) && grantsKubeletProxy(role))
        .map(role => finding(role, 'Grants nodes/proxy access')),
    ];
  },
  RBAC006: (resources, config) => {
    const bound = boundRoleRefs(resources, config);
    return [
      ...resources.clusterrole.data
        .filter(role => bound.has(`ClusterRole:${name(role)}`))
        .flatMap(dangerousRBACFindings),
      ...resources.role.data
        .filter(role => bound.has(`Role:${rbacResourceKey(role)}`))
        .flatMap(dangerousRBACFindings),
    ];
  },
  SC002_AKS: resources => resources.storageclass.data.filter(sc => ['kubernetes.io/azure-disk', 'kubernetes.io/azure-file'].includes(json(sc)?.provisioner)).map(sc => finding(sc, 'Azure in-tree provisioner')),
  SC002_EXPANSION: resources => resources.storageclass.data.filter(sc => json(sc)?.allowVolumeExpansion !== true).map(sc => finding(sc, 'Volume expansion disabled')),
  SC003: emptyHandler,
  SEC001: resources => {
    const used = usedSecretKeys(resources);
    return resources.secret.data
      .filter(secret => !name(secret).startsWith('sh.helm.release.v1.') && !name(secret).startsWith('bootstrap-token-') && !name(secret).startsWith('default-token-') && name(secret) !== 'kube-root-ca.crt')
      .filter(secret => !used.has(`${namespace(secret)}/${name(secret)}`) && !used.has(`*/${name(secret)}`))
      .map(secret => finding(secret, 'Secret appears unused'));
  },
  SEC007: resources => resources.namespace.data.filter(ns => !objectLabels(ns)?.['pod-security.kubernetes.io/enforce']).map(ns => finding(ns, 'No pod-security enforce label')),
  SEC018: resources => resources.serviceaccount.data
    .filter(serviceAccount => json(serviceAccount)?.automountServiceAccountToken !== false)
    .map(serviceAccount => finding(
      serviceAccount,
      'Some ServiceAccounts have automountServiceAccountToken enabled, potentially exposing API credentials to Pods.',
      'Some ServiceAccounts have automountServiceAccountToken enabled, potentially exposing API credentials to Pods.',
      {
        yamlPath: 'automountServiceAccountToken',
        yamlValue: json(serviceAccount)?.automountServiceAccountToken ?? 'not set (defaults to true)',
      }
    )),
  SEC022: missingSecretReferenceFindings,
  SEC028: resources => [
    ...resources.pod.data.flatMap(pod => (json(pod)?.spec?.imagePullSecrets || []).map((secret: any) => finding(pod, `imagePullSecret ${secret.name || 'unknown'}`))),
    ...resources.serviceaccount.data.flatMap(sa => (json(sa)?.imagePullSecrets || []).map((secret: any) => finding(sa, `imagePullSecret ${secret.name || 'unknown'}`))),
  ],
  SEC025: emptyHandler,
  SEC026: resources => resources.validatingadmissionpolicy.data
    .filter(policy => !toArray(json(policy)?.spec?.validations).some((validation: any) => stringValue(validation?.expression)))
    .map(policy => finding(policy, 'ValidatingAdmissionPolicy has no CEL validation rules defined.')),
  SEC030: admissionWebhookFindings,
  WRK001: resources => resources.daemonset.data.filter(daemonSet => (json(daemonSet)?.status?.numberReady || 0) < (json(daemonSet)?.status?.desiredNumberScheduled || 0)).map(daemonSet => finding(daemonSet, `${json(daemonSet)?.status?.numberReady || 0}/${json(daemonSet)?.status?.desiredNumberScheduled || 0} ready`)),
  WRK002: resources => resources.deployment.data.filter(deployment => (json(deployment)?.status?.availableReplicas || 0) < (json(deployment)?.spec?.replicas || 1)).map(deployment => finding(deployment, `${json(deployment)?.status?.availableReplicas || 0}/${json(deployment)?.spec?.replicas || 1} available`)),
  WRK003: resources => resources.statefulset.data.filter(statefulSet => (json(statefulSet)?.status?.readyReplicas || 0) < (json(statefulSet)?.status?.replicas || 1)).map(statefulSet => finding(statefulSet, `${json(statefulSet)?.status?.readyReplicas || 0}/${json(statefulSet)?.status?.replicas || 1} ready`)),
  WRK004: resources => resources.horizontalpodautoscaler.data.filter(hpa => !(json(hpa)?.status?.currentMetrics || []).length || (json(hpa)?.status?.conditions || []).some((condition: any) => condition.status === 'False')).map(hpa => finding(hpa, 'HPA has no metrics or unhealthy condition')),
  WRK005: resources => workloadResourceFindings(resources, 'requests'),
  WRK006: pdbCoverageFindings,
  WRK007: workloadProbeFindings,
  WRK008: resources => resources.deployment.data.filter(deployment => !resources.pod.data.some(pod => namespace(pod) === namespace(deployment) && selectorMatches(workloadSelector(deployment), objectLabels(pod)))).map(deployment => finding(deployment, 'Deployment selector matches no pods')),
  WRK009: deploymentLabelConsistencyFindings,
  WRK010: resources => resources.horizontalpodautoscaler.data.filter(hpa => (json(hpa)?.spec?.metrics || []).some((metric: any) => metric.type === 'Resource')).flatMap(hpa => {
    const targetName = json(hpa)?.spec?.scaleTargetRef?.name;
    const workload = allWorkloads(resources).find(item => namespace(item) === namespace(hpa) && name(item) === targetName);
    return workload ? workloadContainers(workload).filter(container => !hasResource(container, 'requests', 'cpu') && !hasResource(container, 'requests', 'memory')).map(container => finding(hpa, `Target container ${container.name} missing requests`)) : [finding(hpa, `Target ${targetName} not found`)];
  }),
  WRK011: resources => resources.verticalpodautoscaler.data.map(vpa => finding(vpa, 'VPA detected; verify update mode and workload requests')),
  WRK012: resources => allWorkloads(resources).filter(workload => Number(json(workload)?.spec?.replicas || 1) > 1 && !resources.poddisruptionbudget.data.some(pdb => namespace(pdb) === namespace(workload) && selectorMatches(json(pdb)?.spec?.selector?.matchLabels, workloadLabels(workload)))).map(workload => finding(workload, 'Replicated workload has no matching PDB')),
  WRK013: (resources, config) => resources.pod.data.flatMap(pod => {
    const specByName = new Map<string, any>(containers(pod, false).map(container => [String(container.name || ''), container]));
    return (json(pod)?.status?.containerStatuses || []).flatMap((status: any) => {
      const reasons: string[] = [];
      const restarts = Number(status?.restartCount || 0);
      if (status?.state?.waiting?.reason === 'CrashLoopBackOff') {
        reasons.push('CrashLoopBackOff');
      }
      if (status?.lastState?.terminated?.reason === 'OOMKilled' || status?.state?.terminated?.reason === 'OOMKilled') {
        reasons.push('OOMKilled');
      }
      if (restarts >= config.thresholds.restartsCritical) {
        reasons.push(`HighRestarts(${restarts})`);
      }
      if (reasons.length === 0) {
        return [];
      }

      const spec = specByName.get(String(status?.name || '')) || {};
      return [finding(
        pod,
        `${reasons.join(', ')} cpuReq=${spec?.resources?.requests?.cpu || ''} cpuLimit=${spec?.resources?.limits?.cpu || ''} memReq=${spec?.resources?.requests?.memory || ''} memLimit=${spec?.resources?.limits?.memory || ''}`
      )];
    });
  }),
  WRK014: resources => workloadResourceFindings(resources, 'limits', true),
  WRK015: resources => allWorkloads(resources).filter(replicatedWorkloadMissingSpread).map(workload => finding(workload, 'Replicated workload defines neither pod anti-affinity nor topology spread constraints')),
  WRK016: resources => allWorkloads(resources).flatMap(recommendedLabelFindings),
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

  const nativeIdHandler = check.id === 'SEC018' ? nativeHandlers[check.id] : undefined;
  if (nativeIdHandler) {
    return resultFromCheck(check, nativeIdHandler(resources, config));
  }

  const items = getResourcesForCheck(check, resources);
  if (!items) {
    return resultFromCheck(check, [], 'skipped', `Resource kind ${check.resourceKind} is not mapped in the plugin yet.`);
  }

  const findings = items.flatMap(resource => {
    const value = resolveExpression(json(resource), check.value);
    const yamlPath = expressionYamlPath(check.value);
    return evaluateOperator(check.operator || 'exists', value, check.expected)
      ? [finding(resource, valueDetails(check, value), check.failMessage, { yamlPath, yamlValue: value })]
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
  const cronJobs = useResourceList<any>(K8s.ResourceClasses.CronJob.useList());
  const daemonSets = useResourceList<any>(K8s.ResourceClasses.DaemonSet.useList());
  const deployments = useResourceList<any>(K8s.ResourceClasses.Deployment.useList());
  const endpoints = useResourceList<any>(K8s.ResourceClasses.Endpoints.useList());
  const endpointSlices = useResourceList<any>(K8s.ResourceClasses.EndpointSlice.useList());
  const events = useOptionalResourceList<any>(EventResource);
  const gateways = useOptionalResourceList<any>(K8s.ResourceClasses.Gateway);
  const hpas = useResourceList<any>(K8s.ResourceClasses.HorizontalPodAutoscaler.useList());
  const httpRoutes = useOptionalResourceList<any>(K8s.ResourceClasses.HTTPRoute);
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
  const mutatingWebhookConfigurations = useOptionalResourceList<any>(MutatingWebhookConfiguration);
  const validatingAdmissionPolicies = useOptionalResourceList<any>(ValidatingAdmissionPolicy);
  const validatingWebhookConfigurations = useOptionalResourceList<any>(ValidatingWebhookConfiguration);
  const excludedNamespaceSet = React.useMemo(
    () => namespaceSet(config.excludedNamespaces),
    [config.excludedNamespaces.join('\n')]
  );
  const filteredClusterRoles = filterResourceState(clusterRoles, excludedNamespaceSet);
  const filteredClusterRoleBindings = filterResourceState(clusterRoleBindings, excludedNamespaceSet);
  const filteredConfigMaps = filterResourceState(configMaps, excludedNamespaceSet);
  const filteredCronJobs = filterResourceState(cronJobs, excludedNamespaceSet);
  const filteredDaemonSets = filterResourceState(daemonSets, excludedNamespaceSet);
  const filteredDeployments = filterResourceState(deployments, excludedNamespaceSet);
  const filteredEndpoints = filterResourceState(endpoints, excludedNamespaceSet);
  const filteredEndpointSlices = filterResourceState(endpointSlices, excludedNamespaceSet);
  const filteredEvents = filterResourceState(events, excludedNamespaceSet);
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
  const filteredMutatingWebhookConfigurations = filterResourceState(mutatingWebhookConfigurations, excludedNamespaceSet);
  const filteredValidatingAdmissionPolicies = filterResourceState(validatingAdmissionPolicies, excludedNamespaceSet);
  const filteredValidatingWebhookConfigurations = filterResourceState(validatingWebhookConfigurations, excludedNamespaceSet);

  const resources: ResourceStates = {
    clusterrole: filteredClusterRoles,
    clusterrolebinding: filteredClusterRoleBindings,
    configmap: filteredConfigMaps,
    cronjob: filteredCronJobs,
    daemonset: filteredDaemonSets,
    deployment: filteredDeployments,
    endpoint: filteredEndpoints,
    endpoints: filteredEndpoints,
    endpointslice: filteredEndpointSlices,
    events: filteredEvents,
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
    validatingadmissionpolicy: filteredValidatingAdmissionPolicies,
    mutatingwebhookconfiguration: filteredMutatingWebhookConfigurations,
    validatingwebhookconfiguration: filteredValidatingWebhookConfigurations,
    'mutatingwebhookconfiguration,validatingwebhookconfiguration': {
      data: [
        ...filteredMutatingWebhookConfigurations.data,
        ...filteredValidatingWebhookConfigurations.data,
      ],
      error: filteredMutatingWebhookConfigurations.error || filteredValidatingWebhookConfigurations.error,
      loading: filteredMutatingWebhookConfigurations.loading || filteredValidatingWebhookConfigurations.loading,
    },
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
    { ...events, label: 'Events' },
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
    { ...mutatingWebhookConfigurations, label: 'MutatingWebhookConfigurations' },
    { ...validatingAdmissionPolicies, label: 'ValidatingAdmissionPolicies' },
    { ...validatingWebhookConfigurations, label: 'ValidatingWebhookConfigurations' },
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

  return {
    checks,
    loading: enabled ? loading : false,
    errors: enabled ? errors : [],
    scanning,
    scanProgress,
    scanLogs,
  };
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

function ScoreHero({
  checks,
  clusterKey,
  completedAt,
}: {
  checks: CheckResult[];
  clusterKey: string;
  completedAt?: string;
}) {
  const score = scoreChecks(checks);
  const scoreColorName = scoreColor(score.value);
  const scannedAt = completedAt ? formatTrendTimestamp(completedAt) : undefined;
  const metricCards = [
    { label: 'Passed', value: score.passed, color: 'success.main' },
    { label: 'Failed', value: score.failed, color: 'error.main' },
    { label: 'Skipped', value: score.skipped, color: 'warning.main' },
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
            {scannedAt && (
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.5 }}>
                Scan ran {scannedAt}
              </Typography>
            )}
          </Box>
        </Stack>
        <Stack
          direction={{ xs: 'column', sm: 'row' }}
          spacing={1.5}
          alignItems="stretch"
          sx={{ flex: 1 }}
        >
          {metricCards.map(card => (
            <Paper
              key={card.label}
              variant="outlined"
              sx={theme => ({
                alignItems: 'center',
                flex: 1,
                justifyContent: 'center',
                minWidth: 120,
                minHeight: 146,
                p: 2,
                borderColor: theme.palette.divider,
                display: 'flex',
                textAlign: 'center',
              })}
            >
              <Stack spacing={0.5} alignItems="center" justifyContent="center">
                <Typography
                  variant="caption"
                  color="text.secondary"
                  sx={{ fontSize: '0.78rem', fontWeight: 800, letterSpacing: 0.2, textTransform: 'uppercase' }}
                >
                  {card.label}
                </Typography>
                <Typography
                  variant="h3"
                  sx={{
                    color: card.color,
                    fontSize: { xs: '2.25rem', md: '2.65rem' },
                    fontWeight: 900,
                    lineHeight: 1,
                  }}
                >
                  {card.value}
                </Typography>
              </Stack>
            </Paper>
          ))}
          <ScoreTrend clusterKey={clusterKey} />
        </Stack>
      </Stack>
    </Paper>
  );
}

function formatTrendTimestamp(completedAt: string): string {
  const date = new Date(completedAt);
  if (Number.isNaN(date.getTime())) {
    return completedAt;
  }

  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function ScoreTrend({ clusterKey }: { clusterKey: string }) {
  const [history, setHistory] = React.useState<StoredScoreHistoryPoint[]>(() => readStoredScoreHistory(clusterKey));

  React.useEffect(() => {
    const updateHistory = () => setHistory(readStoredScoreHistory(clusterKey));

    updateHistory();
    window.addEventListener(SCORE_UPDATED_EVENT, updateHistory);
    window.addEventListener('storage', updateHistory);

    return () => {
      window.removeEventListener(SCORE_UPDATED_EVENT, updateHistory);
      window.removeEventListener('storage', updateHistory);
    };
  }, [clusterKey]);

  if (!history.length) {
    return null;
  }

  const width = 440;
  const height = 112;
  const paddingX = 30;
  const rightPadding = 14;
  const paddingY = 16;
  const chartWidth = width - paddingX - rightPadding;
  const chartHeight = height - paddingY * 2;
  const latest = history[history.length - 1];
  const previous = history.length > 1 ? history[history.length - 2] : null;
  const delta = previous ? latest.value - previous.value : null;
  const localScanLabel = `${history.length} local ${history.length === 1 ? 'scan' : 'scans'}`;
  const points = history.map((point, index) => {
    const x = history.length === 1
      ? paddingX
      : paddingX + (index / (history.length - 1)) * chartWidth;
    const y = paddingY + ((100 - point.value) / 100) * chartHeight;

    return { ...point, x, y };
  });

  return (
    <Paper
      variant="outlined"
      sx={theme => ({
        borderColor: theme.palette.divider,
        flex: { xs: '1 1 auto', sm: 1.8 },
        minWidth: { xs: '100%', sm: 280 },
        p: 1.5,
      })}
    >
      <Stack spacing={0.75}>
        <Stack direction="row" spacing={1} justifyContent="space-between" alignItems="flex-start">
          <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap">
            <Tooltip title="Stored only in this browser's local cache for the active Headlamp cluster. Clearing browser data or using another machine will not keep this trend.">
              <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 800 }}>
                Score trend
              </Typography>
            </Tooltip>
            <Chip label={localScanLabel} size="small" variant="outlined" />
          </Stack>
          {delta !== null && (
            <Typography
              variant="body2"
              sx={theme => ({
                color: delta >= 0 ? theme.palette.success.main : theme.palette.error.main,
                fontWeight: 900,
              })}
            >
              {delta >= 0 ? '+' : ''}{delta}
            </Typography>
          )}
        </Stack>

        <Box
          component="svg"
          role="img"
          aria-label={`KubeBuddy score trend for ${clusterKey}`}
          viewBox={`0 0 ${width} ${height}`}
          sx={{ display: 'block', height: 90, width: '100%' }}
        >
          <line x1={paddingX} x2={width - rightPadding} y1={paddingY} y2={paddingY} stroke="currentColor" strokeOpacity="0.18" />
          <line x1={paddingX} x2={width - rightPadding} y1={paddingY + chartHeight * 0.3} y2={paddingY + chartHeight * 0.3} stroke="currentColor" strokeOpacity="0.12" />
          <line x1={paddingX} x2={width - rightPadding} y1={height - paddingY} y2={height - paddingY} stroke="currentColor" strokeOpacity="0.18" />
          {points.slice(1).map((point, index) => {
            const previousPoint = points[index];

            return (
              <Box
                component="line"
                key={`${point.completedAt}-${index}`}
                x1={previousPoint.x}
                y1={previousPoint.y}
                x2={point.x}
                y2={point.y}
                sx={theme => ({
                  stroke: theme.palette[scoreColor(point.value)].main,
                  strokeLinecap: 'round',
                  strokeWidth: 3,
                })}
              />
            );
          })}
          {points.map(point => (
            <Box
              component="circle"
              key={point.completedAt}
              cx={point.x}
              cy={point.y}
              r={4.5}
              sx={theme => ({
                fill: theme.palette[scoreColor(point.value)].main,
                stroke: theme.palette.background.paper,
                strokeWidth: 2,
              })}
            >
              <title>
                {`${point.value}/100 - ${point.failed} failed checks, ${point.findings} findings - ${formatTrendTimestamp(point.completedAt)}`}
              </title>
            </Box>
          ))}
          <text x="0" y={paddingY + 3} fill="currentColor" opacity="0.65" fontSize="10">100</text>
          <text x="5" y={paddingY + chartHeight * 0.3 + 3} fill="currentColor" opacity="0.55" fontSize="10">70</text>
          <text x="9" y={height - paddingY + 3} fill="currentColor" opacity="0.65" fontSize="10">0</text>
        </Box>

        <Typography variant="caption" color="text.secondary">
          Local cache only.
          <br />
          <Link href="https://radar.kubebuddy.io/" target="_blank" rel="noreferrer">
            Use Radar
          </Link>
          {' '}for team and long-term history.
        </Typography>
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
    finding.yamlSnippet ? 'Problem YAML:' : '',
    finding.yamlPath ? `Path: ${finding.yamlPath}` : '',
    finding.yamlSnippet ? '```yaml' : '',
    finding.yamlSnippet || '',
    finding.yamlSnippet ? '```' : '',
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

function yamlPathLeaf(path: string | undefined): string | undefined {
  if (!path) {
    return undefined;
  }

  return pathSegments(path).at(-1)?.replace(/\[[^\]]+\]$/, '');
}

function ProblemYamlSnippet({ finding }: { finding: Finding }) {
  const highlightedKey = yamlPathLeaf(finding.yamlPath);
  const lines = (finding.yamlSnippet || '').split('\n');
  const highlightedPattern = highlightedKey
    ? new RegExp(`^\\s*${highlightedKey.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}:`)
    : null;
  const highlightedIndex = highlightedPattern
    ? lines.reduce((matchIndex, line, index) => (highlightedPattern.test(line) ? index : matchIndex), -1)
    : -1;

  return (
    <Box
      component="pre"
      sx={theme => ({
        bgcolor: theme.palette.background.default,
        border: `1px solid ${theme.palette.divider}`,
        borderRadius: 1,
        color: theme.palette.text.primary,
        fontFamily: 'monospace',
        fontSize: '0.8125rem',
        lineHeight: 1.55,
        m: 0,
        overflow: 'auto',
        p: 1.25,
        whiteSpace: 'pre',
      })}
    >
      {lines.map((line, index) => {
        const highlighted = index === highlightedIndex;
        return (
          <Box
            component="span"
            key={`${index}-${line}`}
            sx={theme => ({
              bgcolor: highlighted ? theme.palette.error.dark : 'transparent',
              borderRadius: highlighted ? 0.5 : 0,
              color: highlighted ? theme.palette.error.contrastText : 'inherit',
              display: 'block',
              fontWeight: highlighted ? 800 : 'inherit',
              mx: highlighted ? -0.5 : 0,
              px: highlighted ? 0.5 : 0,
            })}
          >
            {line || ' '}
          </Box>
        );
      })}
    </Box>
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
  const messageLabel = finding ? findingMessage(check, finding) : '';
  const showMessageLabel = finding && messageLabel && messageLabel !== finding.details;
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
                {showMessageLabel && (
                  <Box>
                    <Typography variant="caption" color="text.secondary" sx={{ display: 'block', fontWeight: 700 }}>
                      Why KubeBuddy flagged this
                    </Typography>
                    <Typography variant="body2">{messageLabel}</Typography>
                  </Box>
                )}
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

          {finding.yamlSnippet && (
            <Stack spacing={1}>
              <DrawerSectionHeading>Problem YAML</DrawerSectionHeading>
              <Paper variant="outlined" sx={{ p: 2 }}>
                <Stack spacing={1}>
                  {finding.yamlPath && (
                    <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 700 }}>
                      {finding.yamlPath}
                    </Typography>
                  )}
                  <ProblemYamlSnippet finding={finding} />
                </Stack>
              </Paper>
            </Stack>
          )}

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

type FindingsSortColumn = 'resource' | 'namespace' | 'evidence' | 'message';
type FindingsSortDirection = 'asc' | 'desc';

function yamlScalarEvidence(finding: Finding): string | undefined {
  if (!finding.yamlPath || !finding.yamlSnippet) {
    return undefined;
  }

  const leaf = yamlPathLeaf(finding.yamlPath);
  if (!leaf) {
    return finding.yamlPath;
  }

  const pattern = new RegExp(`^\\s*${leaf.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}:\\s*(.*)$`);
  const line = finding.yamlSnippet
    .split('\n')
    .map(item => item.match(pattern))
    .filter((match): match is RegExpMatchArray => Boolean(match))
    .at(-1);
  const value = line?.[1]?.trim();

  return value ? `${finding.yamlPath}: ${value}` : finding.yamlPath;
}

function evidenceLabel(finding: Finding): string {
  return yamlScalarEvidence(finding) || finding.details || '-';
}

function findingSortValue(check: CheckResult, finding: Finding, column: FindingsSortColumn): string {
  if (column === 'resource') {
    return `${finding.resource} ${finding.kind || check.resourceKind}`.toLowerCase();
  }
  if (column === 'namespace') {
    return (finding.namespace || 'cluster scoped').toLowerCase();
  }
  if (column === 'evidence') {
    return evidenceLabel(finding).toLowerCase();
  }
  return findingMessage(check, finding).toLowerCase();
}

function findingMessage(check: CheckResult, finding: Finding): string {
  const details = finding.details.trim();
  const explicitMessage = finding.message?.trim();
  const checkMessage = check.failMessage.trim();

  if (explicitMessage && explicitMessage !== details) {
    return explicitMessage;
  }

  if (checkMessage && checkMessage !== details) {
    return checkMessage;
  }

  return checkMessage || explicitMessage || details;
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
  const [page, setPage] = React.useState(0);
  const [rowsPerPage, setRowsPerPage] = React.useState(10);
  const [isSortPending, setIsSortPending] = React.useState(false);
  const sortTimerRef = React.useRef<number | null>(null);
  const restoredFinding = React.useMemo(
    () => findings.find(item => returnFindingKey && findingKey(item) === returnFindingKey) || null,
    [findings, returnFindingKey]
  );
  const [selectedFinding, setSelectedFinding] = React.useState<Finding | null>(null);
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
  const pagedFindings = React.useMemo(
    () => sortedFindings.slice(page * rowsPerPage, page * rowsPerPage + rowsPerPage),
    [page, rowsPerPage, sortedFindings]
  );
  const requestSort = (column: FindingsSortColumn) => {
    if (sortTimerRef.current) {
      window.clearTimeout(sortTimerRef.current);
    }

    setIsSortPending(true);
    sortTimerRef.current = window.setTimeout(() => {
      if (sortColumn === column) {
        setSortDirection(current => (current === 'asc' ? 'desc' : 'asc'));
      } else {
        setSortColumn(column);
        setSortDirection('asc');
      }
      setPage(0);

      setIsSortPending(false);
      sortTimerRef.current = null;
    }, 30);
  };
  const handlePageChange = (_event: unknown, nextPage: number) => {
    setPage(nextPage);
  };
  const handleRowsPerPageChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setRowsPerPage(Number.parseInt(event.target.value, 10));
    setPage(0);
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

  React.useEffect(
    () => () => {
      if (sortTimerRef.current) {
        window.clearTimeout(sortTimerRef.current);
      }
    },
    []
  );
  React.useEffect(() => {
    const maxPage = Math.max(0, Math.ceil(sortedFindings.length / rowsPerPage) - 1);
    if (page > maxPage) {
      setPage(maxPage);
    }
  }, [page, rowsPerPage, sortedFindings.length]);
  React.useEffect(() => {
    if (!restoredFinding) {
      return;
    }

    const restoredIndex = sortedFindings.findIndex(item => findingKey(item) === findingKey(restoredFinding));
    if (restoredIndex >= 0) {
      setPage(Math.floor(restoredIndex / rowsPerPage));
    }
  }, [restoredFinding, rowsPerPage, sortedFindings]);

  if (findings.length === 0) {
    return <Typography color="success.main">No issues detected.</Typography>;
  }

  return (
    <>
      {isSortPending && (
        <Stack direction="row" spacing={1} alignItems="center" sx={{ color: 'text.secondary' }}>
          <CircularProgress size={16} />
          <Typography variant="body2">Sorting findings</Typography>
        </Stack>
      )}
      <TableContainer
        component={Paper}
        variant="outlined"
        sx={theme => ({
          bgcolor: theme.palette.background.paper,
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
              <TableCell sortDirection={sortColumn === 'evidence' ? sortDirection : false}>
                {sortLabel('evidence', 'Evidence')}
              </TableCell>
              <TableCell sortDirection={sortColumn === 'message' ? sortDirection : false}>
                {sortLabel('message', 'Why flagged')}
              </TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {pagedFindings.map((item, index) => (
              <TableRow
                hover
                key={`${item.resource}-${item.namespace || 'cluster'}-${page}-${index}`}
                onClick={() => setSelectedFinding(item)}
                selected={Boolean(restoredFinding && findingKey(item) === findingKey(restoredFinding))}
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
                <TableCell>
                  <Stack spacing={0.25}>
                    <Typography
                      variant="body2"
                      sx={{ fontFamily: item.yamlPath ? 'monospace' : undefined, overflowWrap: 'anywhere' }}
                    >
                      {evidenceLabel(item)}
                    </Typography>
                  </Stack>
                </TableCell>
                <TableCell>{findingMessage(check, item) || '-'}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {sortedFindings.length > 10 && (
          <TablePagination
            component="div"
            count={sortedFindings.length}
            page={page}
            rowsPerPage={rowsPerPage}
            rowsPerPageOptions={[5, 10, 25, 50]}
            onPageChange={handlePageChange}
            onRowsPerPageChange={handleRowsPerPageChange}
          />
        )}
      </TableContainer>
      <FindingDetailsDrawer
        check={check}
        finding={selectedFinding}
        onClose={() => setSelectedFinding(null)}
      />
    </>
  );
}

function CheckCard({
  check,
  returnFindingKey,
  targeted,
}: {
  check: CheckResult;
  returnFindingKey?: string;
  targeted?: boolean;
}) {
  const failed = check.status === 'failed';
  const skipped = check.status === 'skipped';
  const suppressedCount = check.suppressedFindings?.length || 0;
  const alertSeverity = severityColor(check.severity);
  const cardRef = React.useRef<HTMLDivElement | null>(null);
  const [open, setOpen] = React.useState(Boolean(returnFindingKey || targeted));
  React.useEffect(() => {
    if (returnFindingKey || targeted) {
      setOpen(true);
    }
  }, [returnFindingKey, targeted]);
  React.useEffect(() => {
    if (!targeted || !cardRef.current) {
      return;
    }

    window.requestAnimationFrame(() => {
      cardRef.current?.scrollIntoView({ block: 'start', behavior: 'smooth' });
    });
  }, [targeted]);
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
    <Paper
      ref={cardRef}
      variant="outlined"
      sx={theme => ({
        borderColor: targeted ? theme.palette.primary.main : undefined,
        boxShadow: targeted ? `0 0 0 1px ${theme.palette.primary.main}` : undefined,
        p: 2,
      })}
    >
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
                {suppressedCount > 0 && (
                  <Chip size="small" variant="outlined" color="warning" label={`${suppressedCount} suppressed`} />
                )}
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

function compareChecksById(left: CheckResult, right: CheckResult): number {
  return left.id.localeCompare(right.id, undefined, { numeric: true, sensitivity: 'base' });
}

function ReportSummary({
  checks,
  clusterKey,
  completedAt,
  excludedNamespaces,
  onOpenSection,
  onOpenCheck,
}: {
  checks: CheckResult[];
  clusterKey: string;
  completedAt?: string;
  excludedNamespaces: string[];
  onOpenSection: (section: string) => void;
  onOpenCheck: (check: CheckResult) => void;
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
      <ScoreHero checks={checks} clusterKey={clusterKey} completedAt={completedAt} />
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
                        {(check.suppressedFindings?.length || 0) > 0 && (
                          <Chip size="small" variant="outlined" color="warning" label={`${check.suppressedFindings?.length || 0} suppressed`} />
                        )}
                      </Stack>
                      <Typography variant="body2" sx={{ fontWeight: 700, mt: 0.5, overflowWrap: 'anywhere' }}>
                        {check.name}
                      </Typography>
                      <Typography variant="caption" color="text.secondary">
                        {reportSectionLabel(check.section)}
                      </Typography>
                    </Box>
                    <Button size="small" onClick={() => onOpenCheck(check)}>
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

function KubeBuddyYamlConfigControl({
  config,
  onChange,
}: {
  config: KubeBuddyConfig;
  onChange: (config: KubeBuddyConfig) => void;
}) {
  const fileInputRef = React.useRef<HTMLInputElement | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [importedSummary, setImportedSummary] = React.useState<string | null>(null);

  const applyYaml = React.useCallback(
    (nextYaml: string) => {
      try {
        const nextConfig = cliYamlToConfig(nextYaml);

        onChange(nextConfig);
        setError(null);
        setImportedSummary(
          `${nextConfig.excludedNamespaces.length} namespaces, ${nextConfig.excludedChecks.length} excluded checks, ${nextConfig.trustedRegistries.length} trusted registries`
        );
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unable to parse YAML.');
        setImportedSummary(null);
      }
    },
    [onChange]
  );
  const importYamlFile = React.useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const file = event.target.files?.[0];

      if (!file) {
        return;
      }

      const reader = new FileReader();
      reader.onload = () => applyYaml(String(reader.result || ''));
      reader.onerror = () => setError('Unable to read the selected file.');
      reader.readAsText(file);
      event.target.value = '';
    },
    [applyYaml]
  );
  const exportYaml = React.useCallback(() => {
    const content = configToCliYaml(config);

    downloadTextFile('kubebuddy-config.yaml', content, 'application/x-yaml;charset=utf-8');
  }, [config]);

  return (
    <Paper variant="outlined" sx={{ p: 2 }}>
      <Stack spacing={1.5}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} alignItems={{ xs: 'stretch', sm: 'center' }} justifyContent="space-between">
          <Box>
            <Typography variant="subtitle2" sx={{ fontWeight: 800 }}>
              kubebuddy-config.yaml
            </Typography>
            <Typography variant="body2" color="text.secondary">
              Import a CLI config into the controls below, or export the current settings as YAML.
            </Typography>
          </Box>
          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
            <Button variant="outlined" onClick={() => fileInputRef.current?.click()}>
              Import YAML
            </Button>
            <Button variant="outlined" onClick={exportYaml}>
              Export YAML
            </Button>
          </Stack>
        </Stack>
        <input
          accept=".yaml,.yml,text/yaml,application/x-yaml"
          hidden
          onChange={importYamlFile}
          ref={fileInputRef}
          type="file"
        />
        {error && <Alert severity="error">{error}</Alert>}
        {importedSummary && (
          <Alert severity="info">
            Imported YAML into the settings below: {importedSummary}. Review the values, then save the config.
          </Alert>
        )}
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
  const [renderedSection, setRenderedSection] = React.useState(returnTarget?.section || 'Summary');
  const [targetCheckId, setTargetCheckId] = React.useState<string | null>(returnTarget?.checkId || null);
  const [status, setStatus] = React.useState<StatusFilter>('all');
  const [renderedStatus, setRenderedStatus] = React.useState<StatusFilter>('all');
  const [severity, setSeverity] = React.useState<SeverityFilter>('all');
  const [renderedSeverity, setRenderedSeverity] = React.useState<SeverityFilter>('all');
  const [isViewPending, setIsViewPending] = React.useState(false);
  const viewTimerRef = React.useRef<number | null>(null);
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
  const detailSection = renderedSection === 'Summary' ? 'All' : renderedSection;
  const sectionChecks = detailSection === 'All' ? checks : checks.filter(check => check.section === detailSection);
  const statusFilteredChecks =
    renderedStatus === 'all' ? sectionChecks : sectionChecks.filter(check => check.status === renderedStatus);
  const visibleChecks = [
    ...(renderedSeverity === 'all'
      ? statusFilteredChecks
      : statusFilteredChecks.filter(check => check.severity === renderedSeverity)),
  ].sort(compareChecksById);
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

  const deferViewRender = React.useCallback((render: () => void) => {
    if (viewTimerRef.current) {
      window.clearTimeout(viewTimerRef.current);
    }

    setIsViewPending(true);
    viewTimerRef.current = window.setTimeout(() => {
      render();
      setIsViewPending(false);
      viewTimerRef.current = null;
    }, 30);
  }, []);
  const changeSection = React.useCallback(
    (nextSection: string, nextTargetCheckId: string | null = null) => {
      setSection(nextSection);
      setStatus('all');
      setSeverity('all');
      setTargetCheckId(nextTargetCheckId);
      deferViewRender(() => {
        setRenderedSection(nextSection);
        setRenderedStatus('all');
        setRenderedSeverity('all');
      });
    },
    [deferViewRender]
  );
  const openCheckFromSummary = React.useCallback(
    (check: CheckResult) => {
      changeSection(check.section, check.id);
    },
    [changeSection]
  );
  const changeStatus = React.useCallback(
    (nextStatus: StatusFilter) => {
      setStatus(nextStatus);
      deferViewRender(() => setRenderedStatus(nextStatus));
    },
    [deferViewRender]
  );
  const changeSeverity = React.useCallback(
    (nextSeverity: SeverityFilter) => {
      setSeverity(nextSeverity);
      deferViewRender(() => setRenderedSeverity(nextSeverity));
    },
    [deferViewRender]
  );
  const clearFilters = React.useCallback(() => {
    setStatus('all');
    setSeverity('all');
    deferViewRender(() => {
      setRenderedStatus('all');
      setRenderedSeverity('all');
    });
  }, [deferViewRender]);

  React.useEffect(
    () => () => {
      if (viewTimerRef.current) {
        window.clearTimeout(viewTimerRef.current);
      }
    },
    []
  );

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
            onChange={(_, value) => changeSection(value)}
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
                label={<SectionTabLabel label={reportSectionLabel(item)} failedCount={item === 'Summary' ? 0 : failedCountsBySection[item] || 0} />}
                value={item}
              />
            ))}
          </Tabs>

          {isViewPending ? (
            <Paper variant="outlined" sx={{ p: 3 }}>
              <Stack direction="row" spacing={1.5} alignItems="center">
                <CircularProgress size={22} />
                <Box sx={{ minWidth: 0 }}>
                  <Typography variant="body1">Loading checks</Typography>
                  <Typography variant="body2" color="text.secondary">
                    Preparing the selected report view.
                  </Typography>
                </Box>
              </Stack>
            </Paper>
          ) : renderedSection === 'Summary' ? (
            <ReportSummary
              checks={checks}
              clusterKey={clusterKey}
              completedAt={initialReport?.completedAt}
              excludedNamespaces={excludedNamespaces}
              onOpenCheck={openCheckFromSummary}
              onOpenSection={changeSection}
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
                  onClearAll={clearFilters}
                  onSeverityChange={changeSeverity}
                  onStatusChange={changeStatus}
                />
              </Stack>
              <Stack spacing={2}>
                {visibleChecks.map(check => (
                  <CheckCard
                    check={check}
                    key={check.id}
                    returnFindingKey={returnTarget?.checkId === check.id ? returnTarget.findingKey : undefined}
                    targeted={targetCheckId === check.id}
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
      const configWithYaml = { ...normalizedConfig, rawYaml: configToCliYaml(normalizedConfig) };

      setConfig(configWithYaml);
      storeKubeBuddyConfig(clusterKey, configWithYaml);

      if (
        storedReport &&
        JSON.stringify(configWithYaml) !==
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
      <Stack spacing={2.5} sx={{ pb: { xs: 6, md: 8 } }}>
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
                <ReportExportButton clusterKey={clusterKey} report={storedReport} />
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
  const [savedConfig, setSavedConfig] = React.useState<KubeBuddyConfig>(() => readKubeBuddyConfig(clusterKey));
  const [saved, setSaved] = React.useState(false);

  const updateConfig = React.useCallback(
    (nextConfig: KubeBuddyConfig) => {
      const normalizedConfig = normalizeKubeBuddyConfig(nextConfig);
      const configWithYaml = { ...normalizedConfig, rawYaml: configToCliYaml(normalizedConfig) };

      setConfig(configWithYaml);
    },
    []
  );
  const saveConfig = React.useCallback(() => {
    storeKubeBuddyConfig(clusterKey, config);
    setSavedConfig(config);
    setSaved(true);
    window.setTimeout(() => setSaved(false), 1800);
  }, [clusterKey, config]);
  const resetConfig = React.useCallback(() => {
    setConfig(savedConfig);
    setSaved(false);
  }, [savedConfig]);
  const hasChanges = React.useMemo(
    () => JSON.stringify(normalizeKubeBuddyConfig(config)) !== JSON.stringify(normalizeKubeBuddyConfig(savedConfig)),
    [config, savedConfig]
  );

  React.useEffect(() => {
    const storedConfig = readKubeBuddyConfig(clusterKey);

    setConfig(storedConfig);
    setSavedConfig(storedConfig);
    setSaved(false);
  }, [clusterKey]);

  return (
    <SectionBox title="KubeBuddy Config">
      <Stack spacing={2.5} sx={{ pb: { xs: 6, md: 8 } }}>
        <Stack
          direction={{ xs: 'column', md: 'row' }}
          justifyContent="space-between"
          spacing={2}
          alignItems={{ xs: 'stretch', md: 'flex-start' }}
        >
          <Box>
            <Typography variant="body1">Configure KubeBuddy scan behavior for this Headlamp cluster.</Typography>
            <Typography variant="body2" color="text.secondary">
              Namespace exclusions stay on the scan page. These settings cover the CLI-compatible config for browser scans.
            </Typography>
            <Link href="https://kubebuddy.io/cli/checks/" target="_blank" rel="noreferrer" variant="body2">
              View KubeBuddy check catalog
            </Link>
          </Box>
          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} sx={{ alignSelf: { xs: 'stretch', md: 'flex-start' } }}>
            <Button disabled={!hasChanges} onClick={resetConfig} variant="outlined">
              Reset
            </Button>
            <Button disabled={!hasChanges} onClick={saveConfig} variant="contained">
              Save Config
            </Button>
          </Stack>
        </Stack>
        {saved && <Alert severity="success">Configuration saved.</Alert>}
        <KubeBuddyYamlConfigControl config={config} onChange={updateConfig} />
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
