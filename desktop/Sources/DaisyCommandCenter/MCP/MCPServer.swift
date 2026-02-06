import Foundation
import Network
import GRDB

// MARK: - UI Message (from Claude to UI)
struct UIMessage: Identifiable, Equatable {
    let id: String
    let sessionId: String
    let role: String          // "assistant", "system", "error"
    let content: String
    let timestamp: Date
    var isTyping: Bool = false
    
    init(id: String = UUID().uuidString, sessionId: String, role: String, content: String, isTyping: Bool = false) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isTyping = isTyping
    }
}

// MARK: - MCP Server for Claude Code Integration
// Implements Model Context Protocol over HTTP for tool execution
// Claude sessions communicate with UI by posting messages via this server

class MCPServer: ObservableObject {
    static let shared = MCPServer()
    
    @Published var isRunning = false
    @Published var connectedClients = 0
    
    // Message queue per session - UI subscribes to this
    @Published var sessionMessages: [String: [UIMessage]] = [:]
    @Published var typingIndicators: [String: Bool] = [:]  // sessionId -> isTyping
    @Published var focusStrings: [String: String] = [:]  // sessionId -> current focus
    
    private var listener: NWListener?
    private let port: UInt16 = 9999
    private let queue = DispatchQueue(label: "mcp.server", qos: .userInitiated)
    
    private init() {}
    
    // MARK: - Message Management (for UI)
    
    func getMessages(for sessionId: String) -> [UIMessage] {
        sessionMessages[sessionId] ?? []
    }
    
    func isTyping(sessionId: String) -> Bool {
        typingIndicators[sessionId] ?? false
    }

    func setTyping(sessionId: String, typing: Bool) {
        DispatchQueue.main.async {
            self.typingIndicators[sessionId] = typing
        }
    }

    func clearMessages(for sessionId: String) {
        DispatchQueue.main.async {
            self.sessionMessages[sessionId] = []
        }
    }

    func addUserMessage(sessionId: String, content: String) {
        let message = UIMessage(sessionId: sessionId, role: "user", content: content)
        DispatchQueue.main.async {
            if self.sessionMessages[sessionId] == nil {
                self.sessionMessages[sessionId] = []
            }
            self.sessionMessages[sessionId]?.append(message)

            // Auto-set typing = true when user sends a message

            self.typingIndicators[sessionId] = true
        }
    }
    
    // MARK: - Server Lifecycle
    
    func start() {
        guard !isRunning else { return }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("MCP Server listening on port \(self?.port ?? 0)")
                    case .failed(let error):
                        print("MCP Server failed: \(error)")
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: queue)
            
        } catch {
            print("Failed to start MCP server: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }
    
    // MARK: - Connection Handling
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self?.connectedClients += 1
                }
                self?.receiveData(on: connection)
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    self?.connectedClients = max(0, (self?.connectedClients ?? 1) - 1)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
    
    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.handleRequest(data: data, connection: connection)
            }
            
            if let error = error {
                print("MCP receive error: \(error)")
                return
            }
            
            if !isComplete {
                self?.receiveData(on: connection)
            }
        }
    }
    
    // MARK: - HTTP Request Handling
    
    private func handleRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request")
            return
        }
        
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendErrorResponse(connection: connection, statusCode: 400, message: "Missing request line")
            return
        }
        
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request line")
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        
        // Find body (after empty line)
        var body: String?
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines.dropFirst(emptyLineIndex + 1)
            body = bodyLines.joined(separator: "\r\n")
        }
        
        // Route request
        switch (method, path) {
        case ("GET", "/health"):
            sendJSONResponse(connection: connection, json: ["status": "ok", "server": "daisy-mcp"])
            
        case ("GET", "/tools"):
            sendJSONResponse(connection: connection, json: ["tools": getToolDefinitions()])
            
        case ("POST", "/execute"):
            if let body = body, let bodyData = body.data(using: .utf8) {
                handleToolExecution(bodyData: bodyData, connection: connection)
            } else {
                sendErrorResponse(connection: connection, statusCode: 400, message: "Missing body")
            }
            
        case ("POST", "/mcp"):
            // JSON-RPC endpoint for MCP protocol
            if let body = body, let bodyData = body.data(using: .utf8) {
                handleMCPRequest(bodyData: bodyData, connection: connection)
            } else {
                sendErrorResponse(connection: connection, statusCode: 400, message: "Missing body")
            }
            
        // -------------------------------------------------------------------------------------
        // --------------------------------- REST API (Mobile) --------------------------------
        // -------------------------------------------------------------------------------------

        case ("GET", _) where path.hasPrefix("/api/"):
            handleRESTGet(path: path, connection: connection)

        case ("POST", _) where path.hasPrefix("/api/"):
            if let body = body, let bodyData = body.data(using: .utf8) {
                handleRESTPost(path: path, bodyData: bodyData, connection: connection)
            } else {
                sendErrorResponse(connection: connection, statusCode: 400, message: "Missing body")
            }

        default:
            sendErrorResponse(connection: connection, statusCode: 404, message: "Not found")
        }
    }
    
    // MARK: - Tool Definitions (Simplified Agent)

    private func getToolDefinitions() -> [[String: Any]] {
        return [

            // ==========================================
            // COMMUNICATION TOOLS
            // ==========================================

            [
                "name": "send_message",
                "description": "Send a message to the UI chat. Set done=true (default) to clear the thinking indicator. If message is empty with done=true, just clears the indicator without showing a message.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string", "description": "Your session ID"],
                        "message": ["type": "string", "description": "Message content to display (can be empty to just clear thinking indicator)"],
                        "done": ["type": "boolean", "description": "Set to true (default) to clear thinking indicator, false to keep it showing"],
                        "focus": ["type": "string", "description": "Current focus/activity in 7 words or less"]
                    ],
                    "required": ["session_id"]
                ]
            ],

            // ==========================================
            // DISCOVERY TOOLS
            // ==========================================

            [
                "name": "get_project",
                "description": "Get details of the current project",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ],
            [
                "name": "get_artifact_types",
                "description": "Get all available artifact types with their required parameters and examples.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ],

            // ==========================================
            // ARTIFACT TOOLS (Agent-scoped)
            // ==========================================

            [
                "name": "add_artifact",
                "description": "Add an artifact. Types: code (content OR path + language), markdown (content), image (path), references (links JSON), csv (content). Caption is REQUIRED.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string", "description": "Your session ID"],
                        "type": ["type": "string", "description": "Type: code, markdown, image, references, csv"],
                        "label": ["type": "string", "description": "Display label"],
                        "content": ["type": "string", "description": "Content (code text or markdown text)"],
                        "language": ["type": "string", "description": "Code: programming language (e.g. python, swift)"],
                        "path": ["type": "string", "description": "Filesystem path for file/directory"],
                        "caption": ["type": "string", "description": "REQUIRED: Short description/caption"],
                        "links": ["type": "string", "description": "References: JSON array of {url, caption} objects"]
                    ],
                    "required": ["session_id", "type", "label", "caption"]
                ]
            ],
            [
                "name": "list_artifacts",
                "description": "List all artifacts for this agent",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ],
            [
                "name": "delete_artifact",
                "description": "Delete an artifact by its ID",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string", "description": "Your session ID"],
                        "artifact_id": ["type": "string", "description": "The ID of the artifact to delete"]
                    ],
                    "required": ["session_id", "artifact_id"]
                ]
            ],

            // ==========================================
            // FILE CLAIM TOOLS (for parallel agent coordination)
            // ==========================================

            [
                "name": "claim_files",
                "description": "Claim files for exclusive editing. Claims auto-expire after 2 minutes. ALWAYS claim before editing. If blocked, use check_claims to see when files become available, then retry.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string", "description": "Your session ID"],
                        "files": ["type": "array", "items": ["type": "string"], "description": "Array of file paths to claim"]
                    ],
                    "required": ["session_id", "files"]
                ]
            ],
            [
                "name": "release_files",
                "description": "Release your claims on files so other agents can edit them. Call after editing. Claims auto-expire after 2 minutes anyway.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string", "description": "Your session ID"],
                        "files": ["type": "array", "items": ["type": "string"], "description": "Array of file paths to release. Omit to release ALL your claims."]
                    ],
                    "required": ["session_id"]
                ]
            ],
            [
                "name": "check_claims",
                "description": "Check if specific files are available to claim. Returns status for each file and seconds until expiry if blocked. Use this before claim_files to avoid errors.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string", "description": "Your session ID"],
                        "files": ["type": "array", "items": ["type": "string"], "description": "Array of file paths to check"]
                    ],
                    "required": ["session_id", "files"]
                ]
            ],
            [
                "name": "list_claims",
                "description": "List all current file claims in the project. Shows which files are claimed by which agents and when they expire.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string", "description": "Your session ID"]
                    ],
                    "required": ["session_id"]
                ]
            ]
        ]
    }
    
    // MARK: - Tool Execution
    
    private func handleToolExecution(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let toolName = json["tool"] as? String,
              let params = json["params"] as? [String: Any] else {
            sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request format")
            return
        }
        
        let result = executeTool(name: toolName, params: params)
        sendJSONResponse(connection: connection, json: result)
    }
    
    private func handleMCPRequest(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendJSONRPCError(connection: connection, id: nil, code: -32600, message: "Invalid JSON")
            return
        }
        
        guard let method = json["method"] as? String else {
            sendJSONRPCError(connection: connection, id: json["id"], code: -32600, message: "Missing method")
            return
        }
        
        let id = json["id"]
        let params = json["params"] as? [String: Any] ?? [:]
        
        switch method {
        case "initialize":
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": [
                    "protocolVersion": "2024-11-05",
                    "serverInfo": [
                        "name": "daisy-mcp",
                        "version": "1.0.0"
                    ],
                    "capabilities": [
                        "tools": [:]
                    ]
                ]
            ]
            sendJSONResponse(connection: connection, json: response)
            
        case "tools/list":
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": [
                    "tools": getToolDefinitions()
                ]
            ]
            sendJSONResponse(connection: connection, json: response)
            
        case "tools/call":
            guard let toolName = params["name"] as? String,
                  let arguments = params["arguments"] as? [String: Any] else {
                sendJSONRPCError(connection: connection, id: id, code: -32602, message: "Invalid params")
                return
            }
            
            let result = executeTool(name: toolName, params: arguments)
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": [
                    "content": [
                        ["type": "text", "text": formatResult(result)]
                    ]
                ]
            ]
            sendJSONResponse(connection: connection, json: response)
            
        default:
            sendJSONRPCError(connection: connection, id: id, code: -32601, message: "Method not found")
        }
    }
    
    private func formatResult(_ result: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: result)
    }
    
    // MARK: - Tool Implementation

    // Extract project ID from session ID
    // Format: agent-{projectId} (default) or agent-{projectId}_{agentId} (non-default)

    private func extractProjectId(from sessionId: String) -> String? {
        guard sessionId.hasPrefix("agent-") else { return nil }
        let remainder = String(sessionId.dropFirst("agent-".count))

        // If contains underscore, project ID is before it

        if let underscoreIndex = remainder.firstIndex(of: "_") {
            return String(remainder[..<underscoreIndex])
        }
        return remainder
    }

    // Extract agent ID from session ID, looking up default agent if needed

    @MainActor
    private func extractAgentId(from sessionId: String, store: DataStore) -> String? {
        guard sessionId.hasPrefix("agent-") else { return nil }
        let remainder = String(sessionId.dropFirst("agent-".count))

        // If contains underscore, agent ID is after it

        if let underscoreIndex = remainder.firstIndex(of: "_") {
            return String(remainder[remainder.index(after: underscoreIndex)...])
        }

        // Default agent - look up by project ID

        let projectId = remainder
        return store.agents.first { $0.projectId == projectId && $0.isDefault }?.id
    }

    // Validate that an agent belongs to the given project

    @MainActor
    private func validateAgentOwnership(agentId: String, projectId: String, store: DataStore) -> String? {
        guard let agent = store.agents.first(where: { $0.id == agentId }) else {
            return "Agent not found"
        }
        if agent.projectId != projectId {
            return "Access denied: Agent belongs to a different project"
        }
        return nil
    }

    // Validate that an artifact belongs to an agent in the given project

    @MainActor
    private func validateArtifactOwnership(artifactId: String, projectId: String, store: DataStore) -> String? {
        guard let artifact = store.getArtifact(artifactId) else {
            return "Artifact not found"
        }
        return validateAgentOwnership(agentId: artifact.taskId, projectId: projectId, store: store)
    }

    private func executeTool(name: String, params: [String: Any]) -> [String: Any] {
        // All DataStore access must happen on main thread
        return DispatchQueue.main.sync { () -> [String: Any] in
            let store = DataStore.shared

            // Extract project ID from session for ownership validation
            let sessionId = params["session_id"] as? String
            let agentProjectId = sessionId.flatMap { extractProjectId(from: $0) }

            // All tools available to the unified Agent (no persona restrictions)

            switch name {

            // ==========================================
            // COMMUNICATION TOOLS
            // ==========================================

            case "send_message":
                guard let sessionId = params["session_id"] as? String else {
                    return ["error": "session_id required"]
                }

                let messageContent = params["message"] as? String ?? ""
                let done = params["done"] as? Bool ?? true

                // Update focus if provided

                if let focus = params["focus"] as? String, !focus.isEmpty {
                    self.focusStrings[sessionId] = focus
                }

                // Clear typing indicator if done

                if done {
                    self.typingIndicators[sessionId] = false
                }

                // If message is empty, just clear indicator and return

                if messageContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return ["success": true, "done": done]
                }

                // Parse session_id to determine the target agent
                // Format: agent-{projectId} (default) or agent-{projectId}_{agentId} (non-default)

                let targetAgentId: String?

                if sessionId.hasPrefix("agent-") {
                    let remainder = String(sessionId.dropFirst("agent-".count))

                    if remainder.contains("_") {

                        // Non-default agent: agent-{projectId}_{agentId}

                        let parts = remainder.split(separator: "_", maxSplits: 1)
                        targetAgentId = String(parts[1])
                    } else {

                        // Default agent: agent-{projectId}

                        let projectId = remainder
                        targetAgentId = store.agents.first { $0.projectId == projectId && $0.isDefault }?.id
                    }
                } else {
                    targetAgentId = store.currentAgentId
                }

                // Add to DataStore messages for this agent

                store.addMessage(role: "daisy", text: messageContent, persona: "agent", toAgentId: targetAgentId)

                // Also add to sessionMessages for backwards compatibility

                let role = params["role"] as? String ?? "assistant"
                let message = UIMessage(sessionId: sessionId, role: role, content: messageContent)
                if self.sessionMessages[sessionId] == nil {
                    self.sessionMessages[sessionId] = []
                }
                self.sessionMessages[sessionId]?.append(message)

                return ["success": true, "message_id": message.id, "done": done]

            // ==========================================
            // ARTIFACT TOOLS
            // ==========================================

            case "add_artifact":
                guard let type = params["type"] as? String,
                      let label = params["label"] as? String,
                      let artifactCaption = params["caption"] as? String else {
                    return ["error": "type, label, and caption are all required"]
                }

                // Map type-specific params to file/path/language fields

                let fileContent: String
                let artifactPath: String?
                let artifactLanguage: String?

                switch type {
                case "code":

                    // Code supports inline content OR path (file/directory)

                    let content = params["content"] as? String
                    let path = params["path"] as? String
                    if content == nil && path == nil {
                        return ["error": "code type requires 'content' or 'path' param"]
                    }
                    fileContent = content ?? ""
                    artifactPath = path
                    artifactLanguage = params["language"] as? String ?? "plaintext"

                case "markdown":
                    guard let content = params["content"] as? String else {
                        return ["error": "markdown type requires 'content' param"]
                    }
                    fileContent = content
                    artifactPath = nil
                    artifactLanguage = nil

                case "image":
                    guard let path = params["path"] as? String else {
                        return ["error": "image type requires 'path' param"]
                    }
                    fileContent = ""
                    artifactPath = path
                    artifactLanguage = nil

                case "references":
                    guard let links = params["links"] as? String else {
                        return ["error": "references type requires 'links' param (JSON array)"]
                    }
                    fileContent = links
                    artifactPath = nil
                    artifactLanguage = nil

                case "csv":
                    guard let content = params["content"] as? String, !content.isEmpty else {
                        return ["error": "csv type requires non-empty 'content' param with CSV data"]
                    }
                    fileContent = content
                    artifactPath = params["path"] as? String
                    artifactLanguage = nil

                default:
                    fileContent = params["content"] as? String ?? ""
                    artifactPath = nil
                    artifactLanguage = nil
                }

                // Artifacts are agent-scoped — use agent ID from session, not UI selection

                let agentId: String
                if let sid = sessionId, let extracted = self.extractAgentId(from: sid, store: store) {
                    agentId = extracted
                } else if let current = store.currentAgentId {
                    agentId = current
                } else {
                    return ["error": "No agent selected"]
                }

                // Upsert: update existing artifact if same label+type exists on this agent

                if let existing = store.findArtifactByLabelAndType(taskId: agentId, label: label, type: type) {
                    store.updateArtifactFull(existing.id, content: fileContent, path: artifactPath, language: artifactLanguage, caption: artifactCaption)
                    return ["success": true, "artifact_id": existing.id, "updated": true]
                }

                // CSV needs special handling for maxRows

                if type == "csv" {
                    store.addCSVArtifact(taskId: agentId, label: label, content: fileContent, path: artifactPath, maxRows: 50, isDeliverable: false)
                    return ["success": true]
                }

                let artifactId = store.addArtifact(
                    taskId: agentId,
                    type: type,
                    label: label,
                    content: fileContent,
                    isDeliverable: false,
                    path: artifactPath,
                    language: artifactLanguage,
                    caption: artifactCaption
                )
                return ["success": true, "artifact_id": artifactId ?? ""]

            case "list_artifacts", "list_task_artifacts":

                // Use agent ID from session, not UI selection

                let agentId: String
                if let sid = sessionId, let extracted = self.extractAgentId(from: sid, store: store) {
                    agentId = extracted
                } else if let current = store.currentAgentId {
                    agentId = current
                } else {
                    return ["error": "No agent selected"]
                }
                let agentArtifactList = store.agentArtifacts[agentId] ?? []
                let formatted = agentArtifactList.isEmpty
                    ? "No artifacts for task \(agentId)"
                    : agentArtifactList.map { "- **\($0.label)** [id: \($0.id)] (type: \($0.type))" }.joined(separator: "\n")
                return ["success": true, "artifacts": formatted]

            case "delete_artifact":
                guard let artifactId = params["artifact_id"] as? String else {
                    return ["error": "artifact_id is required"]
                }

                // Validate artifact belongs to agent's project

                if let projId = agentProjectId {
                    if let error = validateArtifactOwnership(artifactId: artifactId, projectId: projId, store: store) {
                        return ["error": error]
                    }
                }

                guard store.getArtifact(artifactId) != nil else {
                    return ["error": "Artifact not found: \(artifactId)"]
                }
                store.deleteArtifact(artifactId)
                return ["success": true, "deleted": artifactId]

            // ==========================================
            // FILE CLAIM TOOLS
            // ==========================================

            case "claim_files":
                guard let files = params["files"] as? [String], !files.isEmpty else {
                    return ["error": "files array is required and cannot be empty"]
                }

                guard let agentId = store.currentAgentId else {
                    return ["error": "No agent selected"]
                }

                let result = store.claimFiles(files, agentId: agentId)
                if result.success {
                    return ["success": true, "message": result.message]
                } else {
                    return ["error": result.message]
                }

            case "release_files":
                guard let agentId = store.currentAgentId else {
                    return ["error": "No agent selected"]
                }

                let result: (success: Bool, message: String)
                if let files = params["files"] as? [String], !files.isEmpty {
                    result = store.releaseFiles(files, agentId: agentId)
                } else {
                    result = store.releaseAllFiles(agentId: agentId)
                }

                if result.success {
                    return ["success": true, "message": result.message]
                } else {
                    return ["error": result.message]
                }

            case "list_claims":
                store.loadFileClaims()
                let formatted = store.listClaimsFormatted()
                return ["success": true, "claims": formatted]

            case "check_claims":
                guard let files = params["files"] as? [String], !files.isEmpty else {
                    return ["error": "files array is required"]
                }

                guard let agentId = store.currentAgentId else {
                    return ["error": "No agent selected"]
                }

                let result = store.checkClaims(files, agentId: agentId)
                return ["success": true, "files": result]

            // ==========================================
            // PROJECT TOOLS
            // ==========================================
            case "get_project":
                guard let projectId = store.currentProjectId,
                      let project = store.projects.first(where: { $0.id == projectId }) else {
                    return ["error": "No project selected"]
                }
                return [
                    "success": true,
                    "project": [
                        "id": project.id,
                        "name": project.name,
                        "description": project.description,
                        "sourceUrl": project.sourceUrl,
                        "localPath": project.localPath
                    ]
                ]

            // ==========================================
            // DISCOVERY TOOLS
            // ==========================================
            case "get_persona_info":
                guard let persona = params["persona"] as? String else {
                    return ["error": "persona required: 'manager', 'engineer', 'executor', or 'all'"]
                }
                return self.getPersonaInfo(persona)

            case "get_artifact_types":
                return self.getArtifactTypes()

            default:
                return ["error": "Unknown tool: \(name)"]
            }
        }
    }
    
    // MARK: - Response Helpers
    
    private func sendJSONResponse(connection: NWConnection, json: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let body = String(data: data, encoding: .utf8) else {
            sendErrorResponse(connection: connection, statusCode: 500, message: "Failed to serialize response")
            return
        }
        
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendErrorResponse(connection: NWConnection, statusCode: Int, message: String) {
        let body = "{\"error\": \"\(message)\"}"
        let response = """
        HTTP/1.1 \(statusCode) Error\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendJSONRPCError(connection: NWConnection, id: Any?, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        sendJSONResponse(connection: connection, json: response)
    }
    // -------------------------------------------------------------------------------------
    // --------------------------------- REST API Handlers --------------------------------
    // -------------------------------------------------------------------------------------

    // MARK: - REST GET Handler

    private func handleRESTGet(path: String, connection: NWConnection) {
        let result: [String: Any] = DispatchQueue.main.sync {
            let store = DataStore.shared
            let db = DatabaseManager.shared
            let formatter = ISO8601DateFormatter()

            // GET /api/projects

            if path == "/api/projects" {
                let projects: [[String: Any]] = store.projects.map { p in
                    let agents = (try? db.read { db in
                        try DBTask.filter(Column("projectId") == p.id).fetchAll(db)
                    }) ?? []
                    let agentCount = agents.count
                    let thinkingCount = agents.filter { agent in
                        let sessionId = agent.isDefault
                            ? ClaudeCodeManager.agentSessionId(projectId: p.id)
                            : ClaudeCodeManager.agentSessionId(projectId: p.id, agentId: agent.id)
                        return self.typingIndicators[sessionId] == true
                    }.count

                    return [
                        "id": p.id,
                        "name": p.name,
                        "description": p.description,
                        "localPath": p.localPath,
                        "order": p.order,
                        "createdAt": formatter.string(from: p.createdAt),
                        "agentCount": agentCount,
                        "activeAgentCount": thinkingCount
                    ] as [String: Any]
                }
                return ["projects": projects]
            }

            // GET /api/projects/{id}/agents

            if path.hasPrefix("/api/projects/") && path.hasSuffix("/agents") {
                let projectId = String(path.dropFirst("/api/projects/".count).dropLast("/agents".count))
                let agents: [DBTask] = (try? db.read { db in
                    try DBTask.filter(Column("projectId") == projectId).fetchAll(db)
                }) ?? []

                let sorted = agents.sorted { a, b in
                    if a.isDefault { return true }
                    if b.isDefault { return false }
                    return a.createdAt < b.createdAt
                }

                let result: [[String: Any]] = sorted.map { a in
                    let sessionId = a.isDefault
                        ? ClaudeCodeManager.agentSessionId(projectId: projectId)
                        : ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: a.id)
                    let isThinking = self.typingIndicators[sessionId] == true
                    let focus = self.focusStrings[sessionId]
                    let sessionRunning = ClaudeCodeManager.shared.sessions[sessionId]?.isRunning == true

                    return [
                        "id": a.id,
                        "projectId": a.projectId,
                        "title": a.title,
                        "description": a.description,
                        "isDefault": a.isDefault,
                        "isFinished": a.isFinished,
                        "status": a.status,
                        "createdAt": formatter.string(from: a.createdAt),
                        "isThinking": isThinking,
                        "focus": focus ?? "",
                        "sessionRunning": sessionRunning
                    ] as [String: Any]
                }
                return ["agents": result]
            }

            // GET /api/agents/{id}/messages?limit=50

            if path.hasPrefix("/api/agents/") && path.contains("/messages") {
                let pathPart = path.components(separatedBy: "?").first ?? path
                let agentId = String(pathPart.dropFirst("/api/agents/".count).dropLast("/messages".count))

                // Parse limit from query string

                var limit = 50
                if let queryStart = path.range(of: "?") {
                    let query = String(path[queryStart.upperBound...])
                    for param in query.split(separator: "&") {
                        let kv = param.split(separator: "=", maxSplits: 1)
                        if kv.count == 2 && kv[0] == "limit" {
                            limit = Int(kv[1]) ?? 50
                        }
                    }
                }

                let messages: [DBMessage] = (try? db.read { db in
                    try DBMessage
                        .filter(Column("taskId") == agentId)
                        .order(Column("timestamp").asc)
                        .limit(limit)
                        .fetchAll(db)
                }) ?? []

                let result: [[String: Any]] = messages.map { m in
                    [
                        "id": m.id,
                        "agentId": m.taskId,
                        "role": m.role,
                        "text": m.text,
                        "timestamp": formatter.string(from: m.timestamp),
                        "persona": m.persona
                    ] as [String: Any]
                }
                return ["messages": result]
            }

            // GET /api/status

            if path == "/api/status" {
                let projects: [[String: Any]] = store.projects.map { p in
                    let agents: [DBTask] = (try? db.read { db in
                        try DBTask.filter(Column("projectId") == p.id).fetchAll(db)
                    }) ?? []

                    let agentStatuses: [[String: Any]] = agents.map { a in
                        let sessionId = a.isDefault
                            ? ClaudeCodeManager.agentSessionId(projectId: p.id)
                            : ClaudeCodeManager.agentSessionId(projectId: p.id, agentId: a.id)

                        return [
                            "id": a.id,
                            "title": a.title,
                            "isDefault": a.isDefault,
                            "isThinking": self.typingIndicators[sessionId] == true,
                            "focus": self.focusStrings[sessionId] ?? "",
                            "sessionRunning": ClaudeCodeManager.shared.sessions[sessionId]?.isRunning == true
                        ] as [String: Any]
                    }

                    return [
                        "id": p.id,
                        "name": p.name,
                        "agents": agentStatuses
                    ] as [String: Any]
                }

                return [
                    "projects": projects,
                    "timestamp": formatter.string(from: Date())
                ]
            }

            return ["error": "Not found"]
        }

        if result["error"] != nil {
            sendErrorResponse(connection: connection, statusCode: 404, message: result["error"] as? String ?? "Not found")
        } else {
            sendJSONResponse(connection: connection, json: result)
        }
    }

    // MARK: - REST POST Handler

    private func handleRESTPost(path: String, bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid JSON body")
            return
        }

        let result: [String: Any] = DispatchQueue.main.sync {
            let store = DataStore.shared

            // POST /api/agents/{id}/send

            if path.hasPrefix("/api/agents/") && path.hasSuffix("/send") {
                let agentId = String(path.dropFirst("/api/agents/".count).dropLast("/send".count))
                guard let message = json["message"] as? String, !message.isEmpty else {
                    return ["error": "message is required"]
                }
                guard let projectId = json["projectId"] as? String else {
                    return ["error": "projectId is required"]
                }

                // Find the agent

                let agent = store.agents.first { $0.id == agentId }
                guard let agent = agent else {
                    return ["error": "Agent not found"]
                }

                // Add user message to DB

                store.addMessage(role: "user", text: message, persona: "agent", toAgentId: agentId)

                // Send to tmux session

                let sessionId: String
                if agent.isDefault {
                    sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)
                } else {
                    sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agentId)
                }

                if let session = ClaudeCodeManager.shared.sessions[sessionId] {
                    session.sendLine(message)
                    self.typingIndicators[sessionId] = true
                }

                return ["success": true] as [String: Any]
            }

            return ["error": "Not found"]
        }

        if let error = result["error"] as? String {
            sendErrorResponse(connection: connection, statusCode: 400, message: error)
        } else {
            sendJSONResponse(connection: connection, json: result)
        }
    }

    // MARK: - Persona & Artifact Discovery

    private func getPersonaInfo(_ persona: String) -> [String: Any] {
        let agentInfo: [String: Any] = [
            "name": "Agent",
            "session_prefix": "agent-",
            "role": "Works in the codebase and helps the user accomplish their goals.",
            "responsibilities": [
                "Create artifacts (code, markdown, images, references, CSV)",
                "Work in the codebase using Bash, Read, Write, etc.",
                "Communicate with the user via send_message"
            ],
            "tools": [
                ["name": "send_message", "purpose": "Chat with the user (done=true clears thinking indicator)"],
                ["name": "get_project", "purpose": "Get current project details"],
                ["name": "get_artifact_types", "purpose": "Learn about artifact types"],
                ["name": "add_artifact", "purpose": "Create or update an artifact (upserts by label+type)"],
                ["name": "list_artifacts", "purpose": "List all artifacts"],
                ["name": "delete_artifact", "purpose": "Delete an artifact by ID"],
                ["name": "claim_files", "purpose": "Claim files for exclusive editing (auto-expires in 2 min)"],
                ["name": "release_files", "purpose": "Release your file claims so other agents can edit them"],
                ["name": "check_claims", "purpose": "Check if files are available before claiming"],
                ["name": "list_claims", "purpose": "See all current claims and expiry times"]
            ],
            "artifact_scope": "Agent-level. Each agent has its own artifacts.",
            "file_claims": "ALWAYS claim files before editing. Claims expire after 2 minutes. If blocked, check_claims shows when files become available — retry after expiry."
        ]

        switch persona {
        case "agent", "all":
            return ["success": true, "persona": agentInfo]
        default:
            return ["error": "Unknown persona '\(persona)'. Use 'agent' or 'all'."]
        }
    }

    private func getArtifactTypes() -> [String: Any] {
        return [
            "success": true,
            "who_can_create": "The Agent can create artifacts.",
            "upsert_behavior": "If an artifact with the same label and type already exists, it will be updated instead of creating a duplicate.",
            "types": [
                [
                    "type": "code",
                    "description": "Source code — inline text, a single file, or an entire directory.",
                    "required_params": ["session_id", "type", "label", "caption"],
                    "optional_params": ["content", "path", "language"],
                    "modes": [
                        [
                            "mode": "inline",
                            "description": "Pass code directly as text",
                            "params": ["content (the code text)", "language (e.g. python, swift, javascript)"],
                            "example": "--type code --label \"Algorithm\" --content \"def solve(): ...\" --language python --caption \"Main solver\""
                        ],
                        [
                            "mode": "single_file",
                            "description": "Reference a file on disk by absolute path",
                            "params": ["path (absolute path to file)", "language"],
                            "example": "--type code --label \"Config\" --path \"/Users/me/project/config.py\" --language python --caption \"App config\""
                        ],
                        [
                            "mode": "directory",
                            "description": "Reference an entire directory. UI renders a VSCode-like file tree explorer with collapsible folders and syntax-highlighted file viewer.",
                            "params": ["path (absolute path to directory)", "language"],
                            "example": "--type code --label \"Project Source\" --path \"/Users/me/project/src\" --language python --caption \"Full source tree\""
                        ]
                    ]
                ],
                [
                    "type": "markdown",
                    "description": "Rich text content rendered as Markdown.",
                    "required_params": ["session_id", "type", "label", "caption", "content"],
                    "example": "--type markdown --label \"Design Doc\" --content \"# Architecture\\n...\" --caption \"System design overview\""
                ],
                [
                    "type": "image",
                    "description": "An image file displayed in the UI.",
                    "required_params": ["session_id", "type", "label", "caption", "path"],
                    "example": "--type image --label \"Screenshot\" --path \"/path/to/screenshot.png\" --caption \"App screenshot\""
                ],
                [
                    "type": "references",
                    "description": "A collection of web links with captions.",
                    "required_params": ["session_id", "type", "label", "caption", "links"],
                    "links_format": "JSON array of objects with 'url' and 'caption' fields",
                    "example": "--type references --label \"Resources\" --links '[{\"url\":\"https://docs.example.com\",\"caption\":\"API Docs\"}]' --caption \"Research links\""
                ],
                [
                    "type": "csv",
                    "description": "Tabular data displayed as a table.",
                    "required_params": ["session_id", "type", "label", "caption", "content"],
                    "example": "--type csv --label \"Results\" --content \"name,score\\nAlice,95\\nBob,87\" --caption \"Test results\""
                ]
            ]
        ]
    }
}

// MARK: - CLI Tool Generator
extension MCPServer {
    /// Generate a shell script that Claude Code can use to call MCP tools
    func generateCLIScript() -> String {
        return """
        #!/bin/bash
        # Daisy CLI - Interface to Daisy MCP Server
        # Usage: daisy <tool_name> [--param value ...]

        MCP_URL="http://localhost:\(port)/execute"

        tool_name="$1"
        shift

        # Use jq if available for proper JSON encoding, otherwise fallback to Python
        json_encode() {
            if command -v jq &> /dev/null; then
                printf '%s' "$1" | jq -Rs .
            elif command -v python3 &> /dev/null; then
                python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1"
            else
                # Basic escaping fallback
                local val="$1"
                val="${val//\\\\/\\\\\\\\}"
                val="${val//\\"/\\\\\\"}"
                val="${val//$'\\n'/\\\\n}"
                val="${val//$'\\r'/\\\\r}"
                val="${val//$'\\t'/\\\\t}"
                echo "\\"$val\\""
            fi
        }

        # Build JSON params using proper encoding
        params="{}"
        if [[ $# -gt 0 ]]; then
            params="{"
            first=true
            while [[ $# -gt 0 ]]; do
                key="${1#--}"
                value="$2"
                encoded_value=$(json_encode "$value")
                if [ "$first" = true ]; then
                    first=false
                else
                    params="$params,"
                fi
                params="$params\\"$key\\":$encoded_value"
                shift 2
            done
            params="$params}"
        fi

        # Make request
        curl -s -X POST "$MCP_URL" \\
            -H "Content-Type: application/json" \\
            -d "{\\"tool\\":\\"$tool_name\\",\\"params\\":$params}"
        """
    }
    
    /// Install CLI script to a path
    func installCLI(to path: String = "/usr/local/bin/daisy") {
        let script = generateCLIScript()
        do {
            try script.write(toFile: path, atomically: true, encoding: .utf8)
            // Make executable
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = ["+x", path]
            try process.run()
            process.waitUntilExit()
            print("Installed Daisy CLI to \(path)")
        } catch {
            print("Failed to install CLI: \(error)")
        }
    }
}
