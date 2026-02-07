# GitHub HTTPS Setup (Cursor)

Use these steps to connect this project to GitHub over HTTPS. Cursor is already connected to your GitHub account, so the first push can use that for authentication.

**Project-only pushes:** The repo `.gitignore` is set up so only the files you’re working on are pushed (ItemUI, ScriptTracker, macros, docs, epic_quests, and the three ItemUI UI files). The rest of the MacroQuest2 instance (config, plugins, modules, mono, binaries, etc.) is ignored.

## 1. Create the repo on GitHub (if you haven’t)

1. Go to [github.com/new](https://github.com/new).
2. Choose a name (e.g. `CoopUI`).
3. Choose **Private** if you want to limit access for now.
4. **Do not** add a README, .gitignore, or license (you already have these locally).
5. Click **Create repository**.

## 2. Run these commands in Cursor

Open the terminal in Cursor (**View → Terminal** or `` Ctrl+` ``). Make sure you’re in the project root (folder that contains `lua`, `Macros`, `docs`).

Replace `YOUR_USERNAME` and `YOUR_REPO` with your GitHub username and repository name.

```powershell
# Initialize Git (only if this folder is not already a repo)
git init

# Add your GitHub repo as origin (HTTPS)
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git

# Stage all files (respects .gitignore)
git add .

# Check what will be committed (optional)
git status

# First commit
git commit -m "Initial commit: CoopUI (ItemUI, ScriptTracker, Auto Loot, Auto Sell)"

# Use main as the default branch
git branch -M main

# Push to GitHub (Cursor/Git may prompt to sign in to GitHub the first time)
git push -u origin main
```

## 3. First push / sign-in

- If Cursor is already connected to GitHub, the push may succeed without extra steps.
- If you’re asked to sign in, choose **GitHub** and complete the browser flow.
- If you’re asked for a password, use a **Personal Access Token** (GitHub → Settings → Developer settings → Personal access tokens) with `repo` scope, not your GitHub password.

## 4. After the first push

- **Sync often:** `git add .` → `git commit -m "message"` → `git push`
- Or use the **Source Control** view in Cursor (branch icon or `Ctrl+Shift+G`) to stage, commit, and push with the UI.

For release workflow and file list, see [RELEASE_AND_DEPLOYMENT.md](RELEASE_AND_DEPLOYMENT.md).
