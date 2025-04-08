---
title: Release Process
parent: Documentation
nav_order: 4
layout: default
---

# 🚀 KubeBuddy powered by KubeDeck Release Process

This page outlines the steps required to release **KubeBuddy powered by KubeDeck** using GitHub Actions to automate publishing to the **PowerShell Gallery**, **Krew plugin repository**, and **documentation updates**.

---

## 🔹 Tagging a New Release

Releases are managed through **Git tags** following [Semantic Versioning](https://semver.org/) (e.g., `v1.0.0`).

### **1️⃣ Create and Push a Tag**

1. **Create a tag locally** (replace `v1.0.0` with the version number):
   ```bash
   git tag v1.0.0
   ```
2. **Push the tag to GitHub**:
   ```bash
   git push origin v1.0.0
   ```
3. **GitHub Actions will trigger automatic deployments**.

---

## 🔹 GitHub Actions Workflows

We use GitHub Actions to automate the release process. Below are the workflows that get triggered when a new tag is pushed:

### **1️⃣ Publish to PowerShell Gallery**
📌 **Workflow:** [Publish Module to PowerShell Gallery](https://github.com/KubeDeckio/KubeBuddy/blob/main/.github/workflows/publish-psgal.yml)  
This workflow:
- Packages the PowerShell module.
- Publishes it to the PowerShell Gallery.

### **2️⃣ Publish Plugin to Krew**
📌 **Workflow:** [Publish Plugin to Krew](https://github.com/KubeDeckio/KubeBuddy/blob/main/.github/workflows/publish-krewplugin.yaml)  
This workflow:
- Packages the `kubectl` plugin.
- Publishes it to Krew and attaches it as a GitHub release asset.

### **3️⃣ Deploy Documentation to GitHub Pages**
📌 **Workflow:** [Deploy Jekyll Site to Pages](https://github.com/KubeDeckio/KubeBuddy/blob/main/.github/workflows/deploy-docs.yml)  
This workflow:
- Builds and deploys the documentation to **GitHub Pages** when updates are pushed to the `docs/` folder.

### **4️⃣ Netlify PR Previews**
- Automatically deploys preview versions of the documentation for **each pull request**.
- A unique preview URL is posted as a comment for easy review.

### **5️⃣ Run PSScriptAnalyzer on PRs**
📌 **Workflow:** [Run PSScriptAnalyzer](https://github.com/KubeDeckio/KubeBuddy/blob/main/.github/workflows/PSScriptAnalyzer.yaml)  
This workflow:
- Runs **PSScriptAnalyzer** on every pull request.
- Scans PowerShell scripts for warnings and errors.
- Prevents faulty code from being merged.

---

## 🔹 Code Quality and Linting

**PSScriptAnalyzer** ensures the PowerShell code is clean before publishing. It:
✅ Scans PowerShell scripts for best practices.  
✅ Reports warnings and errors in GitHub Actions.  
✅ Blocks releases until errors are resolved.

---

## 🔹 GitHub Pages & Documentation Updates

The **Deploy Jekyll Site to Pages** workflow automatically updates documentation when changes are made to the `docs/` folder. This prevents unnecessary builds when the documentation hasn’t changed.

📌 **Trigger Conditions:**
- A commit affecting `docs/` is pushed to `main`.
- The workflow is manually triggered via GitHub Actions.

Netlify builds **preview versions** of documentation for PRs. Always **check the Netlify preview URL** before merging documentation changes.

---

## 🔹 Summary

These workflows automate the release process, ensuring a smooth deployment across multiple platforms. The **PSScriptAnalyzer checks**, **GitHub Actions automation**, and **Netlify PR previews** ensure high-quality releases.

📌 For full details, see the [workflows folder](https://github.com/KubeDeckio/KubeBuddy/tree/main/.github/workflows) in the repository.

---

✅ **Next Steps:** Make sure your release tag is correctly formatted and push it to GitHub to trigger the automated deployment process! 🚀

