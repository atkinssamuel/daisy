# Daisy Command Center - Architecture

## Overview

Daisy Command Center is a native macOS task management application powered by AI agents. It uses a three-agent architecture (PM, Engineer, Executor) communicating through a skill-based system and MCP protocol.

---

## Directory Structure

```
daisy-command-center/
├── Package.swift
├── README.md
├── ARCHITECTURE.md
└── Sources/DaisyCommandCenter/
    ├── App/
    │   ├── DaisyApp.swift              # Entry point, AppDelegate
    │   └── ContentView.swift           # Main layout
    │
    ├── Views/
    │   ├── Sidebar/
    │   │   ├── ProjectsSidebar.swift
    │   │   ├── ProjectRow.swift
    │   │   ├── PersonaRow.swift
    │   │   └── CriteriaSidebar.swift
    │   │
    │   ├── Chat/
    │   │   ├── ChatInterface.swift     # ManagerChatInterface
    │   │   ├── ChatMessageBubble.swift
    │   │   └── ProposalCard.swift
    │   │
    │   ├── Tasks/
    │   │   ├── TasksList.swift
    │   │   ├── TaskDetail.swift
    │   │   ├── TaskListRow.swift
    │   │   └── CriterionRow.swift
    │   │
    │   ├── Artifacts/
    │   │   ├── ArtifactDetailView.swift
    │   │   ├── MarkdownArtifactView.swift
    │   │   ├── CodeArtifactView.swift
    │   │   ├── ImageArtifactView.swift
    │   │   └── CSVArtifactView.swift
    │   │
    │   └── Common/
    │       ├── InputComponents.swift
    │       └── ProjectSettingsSheet.swift
    │
    ├── Services/
    │   ├── Database/
    │   │   └── Database.swift          # GRDB setup, migrations, DataStore
    │   │
    │   ├── Gateway/
    │   │   └── GatewayClient.swift
    │   │
    │   └── Shell/
    │       ├── ShellExecutor.swift
    │       └── ClaudeCodeSession.swift
    │
    ├── MCP/
    │   └── MCPServer.swift             # HTTP server, JSON-RPC 2.0
    │
    └── Utilities/
        ├── Config.swift
        ├── SkillParser.swift
        └── ArtifactTypeHelpers.swift
```

---

## Agent Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Swift App                            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                      │
│  │   PM    │  │Engineer │  │Executor │                      │
│  └────┬────┘  └────┬────┘  └────┬────┘                      │
│       │            │            │                            │
│       │ Skills     │ Skills     │ Skills                     │
│       │ only       │ + Tools    │ only                       │
│       ▼            ▼            ▼                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Swift Skill Execution Layer                ││
│  │  (create_task, add_artifact, validate_criterion, etc.)  ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              │ (Engineer only - tool calls)
                              ▼
                    ┌─────────────────┐
                    │    OpenClaw     │
                    │  Tool Execution │
                    │  (files, shell, │
                    │   web search)   │
                    └─────────────────┘
```

---

## Agent Specifications

### PM (Project Manager)

**Purpose:** Translate user messages into proposals. ALL changes require UI approval.

**Powers:**
- Can PROPOSE changes to project, tasks, criteria
- Can VIEW task details, artifacts, logs (read-only)
- CANNOT directly execute changes - UI handles that
- NO file system access
- NO code execution

**Skills:**
- `send_message` - All output goes through this
- `propose_create` - Propose a new task
- `propose_update` - Propose task changes
- `propose_delete` - Propose task deletion
- `propose_project_update` - Propose project detail changes
- `propose_start` - Propose starting a task
- `propose_finish` - Propose marking task complete
- `view_task` - View task details
- `view_task_artifacts` - View artifacts
- `view_task_logs` - View executor logs
- `list_tasks` - List all tasks

### Engineer

**Purpose:** Do actual work using OpenClaw tools, update project artifacts with results.

**Powers:**
- Full OpenClaw tool access (files, shell, web search, browser, etc.)
- Full control over project artifacts/deliverables
- Logging for async UI updates
- NO task management (can't create/edit/delete tasks)
- NO criteria management

**OpenClaw Tools:**
- `read_file`, `write_file`, `list_files`
- `exec_command`
- `web_search`
- (any other OpenClaw tools)

**Swift Skills:**
- `send_message` - All output goes through this
- `add_deliverable` - Add artifact to project deliverables
- `update_deliverable`, `delete_deliverable`, `list_deliverables`
- `add_log` - Add progress/info/success/error log to UI

### Executor

**Purpose:** Execute tasks autonomously, validate criteria, produce artifacts.

**Powers:**
- Validate/unvalidate AUTO criteria only (not human criteria)
- Add/delete artifacts on current task
- Add/delete artifacts at project level (deliverables)
- Logging for progress updates
- NO task editing
- NO file system access

**Skills:**
- `validate_criterion`, `unvalidate_criterion`
- `add_task_artifact`, `update_task_artifact`, `delete_task_artifact`
- `add_deliverable`, `delete_deliverable`
- `add_log`

---

## Session ID Format

Session IDs identify which agent and context a message belongs to.

### Format Patterns

```
{projectId}-engineer    # For engineer persona
{projectId}-pm          # For project manager persona
{projectId}-{taskId}-executor   # For executor persona
```

### Examples

```
D36B7554-06C4-4D97-8C9E-86BD6556D516-engineer
D36B7554-06C4-4D97-8C9E-86BD6556D516-pm
D36B7554-06C4-4D97-8C9E-86BD6556D516-1A40FAC8-3115-4572-854E-5F555C943F68-executor
```

### Implementation Notes

1. **Engineer Messages** - Project-scoped, not task-scoped. Stored with any task ID from the project.
2. **UI Updates** - MCP `send_message` triggers `addMessage()` on main thread
3. **Engineer System Prompt** - Explicitly told their session ID
4. **MCP Tool Format:**
   ```bash
   curl -s -X POST http://localhost:9999/execute \
     -H "Content-Type: application/json" \
     -d '{"tool": "send_message", "params": {"session_id": "{projectId}-engineer", "message": "Your message"}}'
   ```

---

## MCP Protocol

The MCP server runs on port 9999 and implements JSON-RPC 2.0.

### Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Health check |
| `/tools` | GET | List available tools |
| `/execute` | POST | Execute a tool (legacy) |
| `/mcp` | POST | JSON-RPC 2.0 MCP protocol |

### MCP Methods

| Method | Purpose |
|--------|---------|
| `initialize` | Client capability exchange |
| `tools/list` | Return available tools |
| `tools/call` | Execute a tool |

### Available Tools

**Communication:**
- `send_message` - Send message to UI chat
- `set_typing` - Show/hide typing indicator
- `clear_chat` - Clear session messages

**Tasks:**
- `list_tasks` - List project tasks
- `get_task` - Get task details
- `create_task` - Create new task
- `update_task` - Update task
- `delete_task` - Delete task
- `update_task_status` - Change task status

**Criteria:**
- `list_criteria` - List task criteria
- `verify_criterion` - Mark as verified
- `unverify_criterion` - Mark as unverified
- `add_criterion` - Add new criterion
- `update_criterion` - Update criterion
- `delete_criterion` - Delete criterion

**Engineer Criteria:**
- `eng_list_criteria` - List engineer criteria
- `eng_add_criterion` - Add engineer criterion
- `eng_complete_criterion` - Toggle completion
- `eng_delete_criterion` - Delete criterion
- `eng_clear_completed` - Clear completed

**Artifacts:**
- `add_artifact` - Add artifact to task
- `update_artifact` - Update artifact
- `delete_artifact` - Delete artifact
- `list_artifacts` - List task artifacts

**Project:**
- `get_project` - Get current project details

**UI:**
- `show_notification` - Show UI notification

---

## Skill Reference

### All Agents

```
[[skill:send_message|message=Your message here]]
```

### PM Only

```
# Proposals (ALL require UI approval)
[[skill:propose_create|title=Task Title|description=Description|auto_criteria=crit1,crit2|human_criteria=crit1]]
[[skill:propose_update|task_id=ID|title=...|description=...|auto_criteria=...|human_criteria=...]]
[[skill:propose_delete|task_id=ID]]
[[skill:propose_project_update|name=...|description=...|source_url=...|local_path=...]]
[[skill:propose_start|task_id=ID]]
[[skill:propose_finish|task_id=ID]]

# Read-Only
[[skill:view_task|task_id=ID]]
[[skill:view_task_artifacts|task_id=ID]]
[[skill:view_task_logs|task_id=ID]]
[[skill:list_tasks]]
```

### Engineer Only

```
# Deliverables (project-level)
[[skill:add_deliverable|type=markdown|label=Name|content=...]]
[[skill:update_deliverable|artifact_id=ID|content=new content]]
[[skill:delete_deliverable|artifact_id=ID]]
[[skill:list_deliverables]]

# Typed Artifacts
[[skill:add_code_artifact|task_id=ID|label=Name|content=code|language=python]]
[[skill:add_image_artifact|task_id=ID|label=Name|content=base64|path=/optional/path]]
[[skill:add_csv_artifact|task_id=ID|label=Name|content=csv_data|path=/optional/path|max_rows=10]]

# View Artifacts
[[skill:view_artifact|artifact_id=ID]]
[[skill:get_csv_rows|artifact_id=ID|start=0|count=10]]

# Logging
[[skill:add_log|type=progress|message=Working on...]]
[[skill:add_log|type=info|message=Found something...]]
[[skill:add_log|type=success|message=Completed!]]
[[skill:add_log|type=error|message=Failed because...]]
```

### Executor Only

```
[[skill:validate_criterion|criterion_id=ID]]
[[skill:unvalidate_criterion|criterion_id=ID]]

[[skill:add_task_artifact|type=markdown|label=Name|content=...]]
[[skill:update_task_artifact|artifact_id=ID|content=new content]]
[[skill:delete_task_artifact|artifact_id=ID]]

[[skill:add_deliverable|type=markdown|label=Name|content=...]]
[[skill:delete_deliverable|artifact_id=ID]]

[[skill:add_log|type=progress|message=Working on...]]
```

---

## Formatting Standards

### File Organization

- One primary type per file (exceptions: small related types)
- Files named after primary type
- Max 300 lines per file (split if larger)

### Import Order

1. Foundation/SwiftUI
2. External packages (GRDB, MarkdownUI, Highlightr)
3. Internal modules

### View Structure

```swift
struct MyView: View {
    // 1. Environment objects
    // 2. State/Binding properties
    // 3. Regular properties
    // 4. body
    // 5. Computed properties
    // 6. Private methods
}
```

### Naming

- Views: `*View` suffix (e.g., `TaskDetailView`)
- View Models: `*ViewModel` suffix
- Managers: `*Manager` suffix
- Protocols: `*Protocol` suffix or adjective (e.g., `Loadable`)

### Comments

- Section headers: `// MARK: - Section Name`
- Blank line before and after comments
- No inline comments unless complex logic

---

## Data Storage

- **Database:** `~/.daisy-command-center/daisy.db` (SQLite via GRDB)
- **Models:** DBProject, DBTask, DBArtifact, DBMessage, DBCriterion, DBEngineerCriterion

---

## Implementation Notes

1. **PM uses skill parsing only** - No tool calling needed, just regex parse `[[skill:...]]`

2. **Engineer uses OpenClaw tools + skill parsing** - Route through OpenClaw session for file/shell/web, parse skills for artifact management

3. **Executor uses skill parsing only** - Limited skill set, no tool calling needed

4. **Proposal flow** - PM's `propose_*` skills show confirmation UI, only execute on user approval

5. **Logging** - Engineer and Executor can async update UI via `add_log` skill
