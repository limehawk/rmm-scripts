# tools/lint

Repo-local linters. Not currently wired into CI — run manually or install as
a git pre-commit hook.

## check_strictmode_ordering.ps1

Flags `.ps1` scripts where `Set-StrictMode -Version Latest` fires *before*
SuperOps runtime-variable placeholder reads. That ordering crashes the
script with `VariableIsUndefined` whenever a placeholder isn't injected
(e.g., the tech leaves the runtime variable blank in SuperOps, or the trigger
doesn't register the variable at all).

See `docs/powershell_script_guidelines.md` for the prescribed layout: the
HARDCODED INPUTS block must come *before* `Set-StrictMode`.

**Run:**

```bash
pwsh ./tools/lint/check_strictmode_ordering.ps1
```

Exits 0 if clean, 1 if any violation is found.

## pre-commit hook

Drop-in hook that invokes the linter on any staged `scripts/*.ps1` change.

**Install:**

```bash
ln -sf ../../tools/lint/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

(Or copy instead of symlink if you prefer.) From then on, `git commit`
refuses any `.ps1` change that violates the ordering rule until it's fixed.
