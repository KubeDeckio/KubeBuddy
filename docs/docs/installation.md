---
title: Installation
parent: Documentation
nav_order: 1
layout: default
---

# ⚡ Installing KubeBuddy

KubeBuddy can be installed on **Windows, Linux, and macOS** via the **PowerShell Gallery** or **Krew** for `kubectl` users.

---

## 🖥️ Installing via PowerShell Gallery

For PowerShell users, install **KubeBuddy** directly from the PowerShell Gallery:

```powershell
Install-Module -Name KubeBuddy -Repository PSGallery -Scope CurrentUser
```

### 🔄 Updating KubeBuddy

To update **KubeBuddy** to the latest version:

```powershell
Update-Module -Name KubeBuddy
```

---

## 🌍 Installing via Krew (Linux/macOS)

For Kubernetes users on **Linux and macOS**, install KubeBuddy as a `kubectl` plugin using **Krew**:

### 1️⃣ Install Krew
Follow the official Krew installation guide [here](https://krew.sigs.k8s.io/docs/user-guide/setup/install/).

### 2️⃣ Install KubeBuddy via Krew

```bash
kubectl krew install KubeBuddy
```

### 🔄 Updating KubeBuddy via Krew

```bash
kubectl krew upgrade KubeBuddy
```

---

## 🔧 Requirements

✅ **PowerShell Version**: PowerShell 7 or higher is required.  
✅ **Additional Dependencies**: The `powershell-yaml` module is needed for YAML parsing and will be installed automatically.  
✅ **Krew for Plugin Users**: If using Krew, ensure `kubectl` and Krew are properly configured.  

---

✅ **Next Steps:** Now that KubeBuddy is installed, check out the [Usage Guide](/docs/usage) to start cleaning up your Kubernetes configurations! 🚀

