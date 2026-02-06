# Daisy

Multi-agent AI command center — desktop and mobile.

## Structure

```
daisy/
├── desktop/     # macOS desktop app (Swift/SwiftUI, macOS 14+)
└── mobile/      # iOS companion app (Swift/SwiftUI, iOS 17+)
```

## Desktop

Native macOS application that orchestrates multiple Claude Code agents in parallel. Features a three-column layout (projects, agents, chat+terminal), artifact system, and file claim coordination for safe parallel editing.

### Build & Run

```bash
cd desktop
swift build
swift run DaisyCommandCenter
```

### Dependencies

- **GRDB.swift** — SQLite database
- **swift-markdown-ui** — Markdown rendering
- **Highlightr** — Syntax highlighting

## Mobile

iOS companion app for monitoring projects and tasks remotely.

### Build

```bash
cd mobile
swift build
```
