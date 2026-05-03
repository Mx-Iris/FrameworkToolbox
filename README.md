# FrameworkToolbox

A description of this package.

## Claude Code Plugin

This repository also ships as a [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) plugin marketplace, providing skills that teach Claude Code how to use the macros in this package (currently `@Loggable` and `#log`).

### Install via Claude Code marketplace

Inside Claude Code, run:

```text
/plugin marketplace add Mx-Iris/FrameworkToolbox
/plugin install framework-toolbox@framework-toolbox
```

The first command registers this repository as a marketplace by reading `.claude-plugin/marketplace.json`. The second command installs the `framework-toolbox` plugin from the `framework-toolbox` marketplace, which mounts every skill under `plugins/framework-toolbox/skills/`.

To update the marketplace listing later:

```text
/plugin marketplace update framework-toolbox
```

### Available skills

| Skill | Triggers on |
|-------|-------------|
| `loggable-and-log` | Working with `@Loggable` / `#log`, configuring `subsystem`/`category`/access level, choosing privacy levels, or debugging the pre-macOS 11 `os_log` fallback. |

### Repository layout

```
.claude-plugin/marketplace.json         # marketplace manifest
plugins/framework-toolbox/              # plugin root
  .claude-plugin/plugin.json            # plugin manifest
  skills/                               # auto-discovered skills
    loggable-and-log/SKILL.md
```
