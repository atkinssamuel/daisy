# Daisy Command Center

**Version 2.1.0**

A native macOS task management app powered by AI agents via the OpenClaw gateway.

## Features

- **Project Management** — Organize work into projects
- **AI Project Manager** — Chat interface with an AI PM that can create and manage tasks
- **AI Engineer** — Chat with an AI for quick technical questions with full tool access
- **Task Execution** — AI agents execute tasks and report progress
- **Criteria Tracking** — Auto-verified and human-validated success criteria
- **MCP Integration** — Claude Code can connect via MCP protocol

## Requirements

- macOS 14+
- Swift 5.9+
- OpenClaw gateway running on `http://127.0.0.1:18789`

## Build & Run

```bash
swift build
./.build/arm64-apple-macosx/debug/DaisyCommandCenter
```

## Quick Start

1. Start the OpenClaw gateway
2. Build and run Daisy Command Center
3. Create a new project using the + button
4. Configure project settings (local path, source URL)
5. Chat with the PM to create tasks
6. Chat with the Engineer for technical work

## MCP Server

The app runs an MCP server on port 9999 for Claude Code integration:

```bash
# Test the server
curl http://localhost:9999/health

# Connect Claude Code
claude mcp add --transport http daisy http://localhost:9999/mcp
```

### MCP Protocol Compliance

For Claude Code to access MCP tools natively (e.g., `mcp__daisy__send_message`), tool definitions must use `inputSchema` instead of `parameters`. This is required by the MCP specification.

**Correct format:**
```json
{
  "name": "send_message",
  "description": "Send a message to the UI chat",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_id": {"type": "string"},
      "message": {"type": "string"}
    },
    "required": ["session_id", "message"]
  }
}
```

**Incorrect format (tools won't be accessible natively):**
```json
{
  "name": "send_message",
  "description": "...",
  "parameters": { ... }  // Wrong key - Claude Code ignores these tools
}
```

### Validating MCP Tools

```bash
# Verify tools/list returns inputSchema
curl -s -X POST http://localhost:9999/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | grep -o '"inputSchema"' | head -1

# Test tool execution
curl -s -X POST http://localhost:9999/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"send_message","arguments":{"session_id":"test","message":"hello"}}}'
```

### Testing Native Tool Access in Claude Code

1. Start Claude Code in the project directory
2. Run `/mcp` to verify "daisy ✔ connected"
3. Ask Claude to use a tool: "Call mcp__daisy__send_message with session_id test and message Hello"
4. Claude should use `daisy - send_message (MCP)` directly, not curl

## Data Storage

- Database: `~/.daisy-command-center/daisy.db`

## Documentation

See [ARCHITECTURE.md](ARCHITECTURE.md) for:
- Directory structure
- Agent specifications
- Session ID format
- MCP protocol details
- Skill reference
- Formatting standards

## License

MIT
