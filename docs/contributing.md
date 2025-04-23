---
title: Contributing
parent: Documentation
nav_order: 3
layout: default
---

# 🤝 Contributing to KubeBuddy powered by KubeDeck

🎉 Thank you for considering contributing to **KubeBuddy powered by KubeDeck**! 🎉

We welcome all contributions, whether it’s reporting bugs, suggesting improvements, updating documentation, or submitting code. This guide will help you contribute effectively.

---

## 🚀 Getting Started

### 🔹 Fork & Clone the Repository

1. **Fork** the repository by clicking the **Fork** button at the top-right of this page.
2. **Clone** your forked repository:
   ```bash
   git clone https://github.com/<your-username>/KubeBuddy.git
   cd KubeBuddy
   ```
3. Add the main **KubeBuddy** repository as a remote:
   ```bash
   git remote add upstream https://github.com/KubeDeckio/KubeBuddy.git
   ```

### 🔹 Set Up Your Development Environment

Before contributing, install the required dependencies:

✅ **PowerShell 7 or higher**.  
✅ **Install the powershell-yaml module**:
   ```powershell
   Install-Module -Name powershell-yaml -Scope CurrentUser
   ```

---

## 🛠️ How to Contribute

### 📌 Reporting Bugs

If you find a bug, please **open an issue** with:
- The environment you're using (OS, PowerShell version).
- Steps to reproduce the issue.
- Expected behavior vs actual behavior.

### 📌 Suggesting Features

Have an idea to improve **KubeBuddy powered by KubeDeck**? We’d love to hear it! Open an issue and provide:
- A clear description of the feature.
- Specific use cases where it would be helpful.

### 📌 Creating a Branch

Always create a new branch before making changes:
```bash
git checkout -b feature/my-new-feature
```

### 📌 Submitting a Pull Request (PR)

1. **Test your changes** to ensure they work as expected.
2. Push your branch to your fork:
   ```bash
   git push origin feature/my-new-feature
   ```
3. Open a **Pull Request**:
   - Go to your fork on GitHub and click **"New pull request"**.
   - Choose your branch and submit the PR to the `main` branch of **KubeBuddy**.
   - Provide a **clear and detailed description** of your changes.

### 📌 Code Standards

✅ **Follow PowerShell best practices**.  
✅ **Use meaningful commit messages** (e.g., "Fix issue with cluster cleanup logic" instead of "Fix bug").  
✅ **Comment your code** to explain complex logic.

---

## 🔍 Pull Request Review Process

All contributions will be reviewed by maintainers. Reviews may involve:
- Suggesting improvements.
- Requesting more information.
- Testing changes before merging.

Please be patient, as review times may vary.

---

## 📜 Code of Conduct

We follow a [Code of Conduct](https://github.com/KubeDeckio/KubeBuddy/blob/main/CODE_OF_CONDUCT.md) to ensure a respectful and inclusive community.

---

## 🎉 Thank You!

Your contributions help make **KubeBuddy powered by KubeDeck** better! We appreciate your support in improving the project. 🚀

