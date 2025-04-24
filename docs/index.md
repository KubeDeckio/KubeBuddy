---
template: home.html
title: Documentation
nav_order: 2
layout: default
hide:
  - footer
  - toc
  - navigation
---


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