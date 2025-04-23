---
title: Documentation
nav_order: 2
layout: default
hide:
  - footer
  - toc
  - navigation
---

<style>
.hero {
  text-align: center;
  padding: 2rem 1rem 1rem;
  font-size: 1.15rem;
  line-height: 1.8;
  background: var(--md-primary-fg-color);
  color: white;
  border-radius: 8px;
  margin-bottom: 2rem;
}
.columns {
  display: flex;
  flex-wrap: wrap;
  gap: 2rem;
  margin-bottom: 2rem;
  font-size: 0.9rem;
}
.column {
  flex: 1;
  min-width: 280px;
}
.column table {
  width: 100%;
  border-collapse: collapse;
}
.column table th,
.column table td {
  padding: 0.75rem;
  border-bottom: 1px solid #ccc;
  text-align: left;
}
ul.people-list {
  padding-left: 1rem;
  list-style: none;
}
ul.people-list li::before {
  content: "👤";
  margin-right: 0.5rem;
}
.md-typeset h1 {
  text-align: center;
  font-weight: bold;
}
table.landing-table {
  font-size: 0.9rem;
}
.notice {
  background: #f1f3f4;
  border-left: 6px solid var(--md-primary-fg-color);
  padding: 1rem;
  margin: 2rem 0;
  border-radius: 6px;
  font-size: 1rem;
  color: #333;
}
</style>

# Kubernetes Says Your Cluster is Healthy. It’s Probably Not.

<div class="hero">
  <strong>KubeBuddy powered by KubeDeck</strong><br>
  Runs complete health, security, and configuration checks on your Kubernetes cluster.<br>
  ✅ No agents. No Helm charts. No guesswork.<br>
  ✅ Everything runs from your terminal.
</div>

<div class="columns">

<div class="column">

<h2>🚀 What It Does</h2>

<ul>
  <li><strong>Node and Pod Health</strong>: Find failed nodes, pending pods, crash loops</li>
  <li><strong>Workload Issues</strong>: Spot stuck jobs, terminating pods, bad restarts</li>
  <li><strong>Security Gaps</strong>: Review RBAC, roles, bindings, and risky permissions</li>
  <li><strong>AKS Checks</strong>: Run Microsoft-aligned checks with one flag</li>
  <li><strong>Event Summaries</strong>: Catch warnings, crash loops, controller errors</li>
  <li><strong>Networking and Storage</strong>: Inspect PVCs, services, network policies</li>
  <li><strong>Exportable Reports</strong>: HTML, JSON, and CLI output for audits and automation</li>
</ul>

</div>

<div class="column">

<h2>💡 Why Use It</h2>

<p>You don’t need more metrics. You need answers.</p>

<table class="landing-table">
  <thead>
    <tr>
      <th>What You Use Today</th>
      <th>What You Miss</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>kubectl get pods</code></td>
      <td>Why they're failing</td>
    </tr>
    <tr>
      <td>Readiness probes</td>
      <td>Root service and config issues</td>
    </tr>
    <tr>
      <td>Dashboards</td>
      <td>Silent RBAC issues, warnings</td>
    </tr>
    <tr>
      <td>Manual reviews</td>
      <td>Gaps in consistency and coverage</td>
    </tr>
  </tbody>
</table>

</div>

</div>

<div style="display: flex; align-items: center; gap: 1rem; background: var(--md-default-bg-color); border-left: 6px solid var(--md-primary-fg-color); padding: 1rem 1.5rem; border-radius: 6px; margin: 2rem 0; font-size: 1rem; color: var(--md-default-fg-color); box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);">
  <span style="font-size: 1.5rem;">🧭</span>
  <div>
    <strong>KubeBuddy runs entirely outside the cluster.</strong><br>
    No setup inside Kubernetes. Works with any K8s distro. PowerShell 7+ required.
  </div>
</div>



## 👥 Who It's For

<div style="margin-bottom: 1.5rem; font-size: 1rem;">
<ul class="people-list">
  <li><strong>SREs</strong> reviewing incidents and outages</li>
  <li><strong>Platform engineers</strong> auditing environments regularly</li>
  <li><strong>DevOps teams</strong> integrating health checks into CI/CD</li>
  <li><strong>Operators</strong> without internal observability tooling</li>
</ul>
</div>

## 🛠️ Install and Run

<div class="notice">
  <p><strong>Install with PowerShell 7+:</strong></p>
  <pre><code>Install-Module -Name KubeBuddy -Repository PSGallery -Scope CurrentUser</code></pre>
  <p style="margin-top: 0.75rem;">
    Runs on <strong>macOS</strong>, <strong>Linux</strong>, and <strong>Windows</strong>.  
    Requires <code>PowerShell 7+</code> and access to your kubeconfig.
  </p>
</div>