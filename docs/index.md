---
title: KubeBuddy Documentation
nav_order: 1
layout: default
hide:
  - footer
  - toc
  - navigation
---

# Kubernetes Says Your Cluster is Healthy. It’s Probably Not.

<div class="hero">
  <h1>KubeBuddy by KubeDeck</h1>
  Complete health, security, and configuration checks for your Kubernetes cluster.<br>
  ✅ No agents. No Helm charts. Runs from your terminal.<br>
  <a href="/getting-started" class="cta-button">Get Started</a>
</div>

<div class="columns">

<div class="column">
  <h2>🚀 What It Does</h2>
  <div class="md-card">
    <ul>
      <li><strong>Health Checks</strong>: Detect failed nodes, pending pods, crash loops.</li>
      <li><strong>Security</strong>: Audit RBAC, roles, and risky permissions.</li>
      <li><strong>AKS Support</strong>: Microsoft-aligned checks with one flag.</li>
      <li><strong>Reports</strong>: Export HTML, JSON, or CLI output for audits.</li>
    </ul>
  </div>
</div>

<div class="column">
  <h2>💡 Why Use It</h2>
  <p>You don’t need more metrics. You need answers.</p>
  <table class="landing-table">
    <thead>
      <tr>
        <th>Current Tools</th>
        <th>What You Miss</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><code>kubectl get pods</code></td>
        <td>Why pods fail</td>
      </tr>
      <tr>
        <td>Readiness probes</td>
        <td>Root config issues</td>
      </tr>
      <tr>
        <td>Dashboards</td>
        <td>Silent RBAC issues</td>
      </tr>
    </tbody>
  </table>
</div>

</div>

<div class="notice">
  <p><strong>Runs Outside Your Cluster</strong></p>
  No setup inside Kubernetes. Works with any K8s distro. Requires PowerShell 7+.
</div>

## 👥 Who It's For

<ul class="people-list">
  <li><strong>SREs</strong>: Review incidents and outages.</li>
  <li><strong>Platform Engineers</strong>: Audit environments.</li>
  <li><strong>DevOps Teams</strong>: Integrate into CI/CD.</li>
  <li><strong>Operators</strong>: No observability tools needed.</li>
</ul>

## 🛠️ Install and Run

<div class="notice">
  <p><strong>Install with PowerShell 7+:</strong></p>
  <pre><code>Install-Module -Name KubeBuddy -Repository PSGallery -Scope CurrentUser</code></pre>
  <p>Runs on <strong>macOS</strong>, <strong>Linux</strong>, and <strong>Windows</strong>. Requires <code>PowerShell 7+</code> and kubeconfig access.</p>
</div>