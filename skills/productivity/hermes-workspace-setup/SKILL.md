---
name: hermes-workspace-setup
description: Set up Hermes workspace root and task subfolders.
category: productivity
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: []
    related_skills: []
---

## When to Use
You want to start a new task with Hermes Agent and keep its files, notes, and artifacts isolated in a dedicated folder under a common workspace root (e.g., `~/Documents/ProjectByHermes`).

## Steps
1. **Choose a workspace root** (if not already set). A common location is `~/Documents/ProjectByHermes` (Windows: `%USERPROFILE%\Documents\ProjectByHermes`).
2. **Ensure the root exists**:
   ```bash
   mkdir -p "$HOME/Documents/ProjectByHermes"
   ```
   (Adjust path for your OS; on Windows using Git Bash you can use `/c/Users/<user>/Documents/ProjectByHermes`.)
3. **Create a task subfolder**:
   - Derive a folder name from the task title: lowercase, replace spaces with hyphens, remove special characters.
   - Example: task title “Create a web scraper for news” → folder `create-a-web-scraper-for-news`.
   - Command:
     ```bash
     TASK_NAME="Create a web scraper for news"
     SLUG=$(echo "$TASK_NAME" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g')
     mkdir -p "$HOME/Documents/ProjectByHermes/$SLUG"
     ```
4. **Set the working directory** for subsequent Hermes tool calls (terminal, file ops, etc.) to this subfolder. In Hermes you can do this by specifying `workdir` in tool calls, or by changing the shell's cwd before invoking the agent.
5. **Proceed with your task**; all files created via Hermes will land inside this task folder unless you explicitly specify another path.

## Pitfalls
- Forgetting to slugify the task name can lead to folders with spaces or special characters that cause issues in scripts.
- If you reuse an existing task name without realizing it, you may overwrite previous work. Consider appending a timestamp or version if you need to keep multiple attempts.
- On Windows, ensure you use a POSIX-compatible shell (Git Bash) when running the `mkdir` and slugification commands; otherwise use PowerShell equivalents.

## Verification
After running the steps, check that the folder exists:
```bash
ls -ld "$HOME/Documents/ProjectByHermes/$SLUG"
```
You should see a directory with the proper permissions.

## Example
User says: “Set up a workspace for analyzing a CSV file.”
- Root: `/home/user/Documents/ProjectByHermes`
- Slug: `analyzing-a-csv-file`
- Commands executed:
  ```bash
  mkdir -p /home/user/Documents/ProjectByHermes
  TASK_NAME="Analyzing a CSV file"
  SLUG=$(echo "$TASK_NAME" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g')
  mkdir -p /home/user/Documents/ProjectByHermes/$SLUG
  ```
- Subsequent file reads/writes should use `/home/user/Documents/ProjectByHermes/analyzing-a-csv-file` as the base path.

---