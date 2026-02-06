import Foundation
import GRDB

// MARK: - Data Store (Observable wrapper around database)

@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()
    
    @Published var projects: [DBProject] = []
    @Published var currentProjectId: String?
    @Published var currentTaskId: String?
    
    // Thinking state for individual task executors
    @Published var thinkingTaskId: String? = nil
    
    // Current project's tasks
    @Published var tasks: [DBTask] = []
    
    // Per-agent message cache for instant switching
    @Published var agentMessages: [String: [DBMessage]] = [:]
    @Published var logs: [DBTaskLog] = []

    // Criteria and artifacts are computed from cache for instant task switching
    var criteria: [DBCriterion] {
        guard let taskId = currentTaskId else { return [] }
        return taskCriteria[taskId] ?? []
    }

    var artifacts: [DBArtifact] {
        guard let taskId = currentTaskId else { return [] }
        return taskArtifacts[taskId] ?? []
    }
    
    // Pending proposals from PM awaiting confirmation (queue, processed sequentially)
    @Published var pendingProposals: [PendingProposal] = []

    // Only show proposals for the current project
    var pendingProposal: PendingProposal? {
        pendingProposals.first { $0.projectId == currentProjectId }
    }
    
    // Project-level artifacts (deliverables)
    @Published var deliverables: [DBArtifact] = []

    // Project settings sheet
    @Published var showProjectSettings: Bool = false

    // MARK: - Agent Aliases (agents are stored as tasks)

    // Current agent ID (alias for currentTaskId)
    var currentAgentId: String? {
        get { currentTaskId }
        set { currentTaskId = newValue }
    }

    // All agents for current project (sorted: default first, then by creation date)
    var agents: [DBAgent] {
        tasks.sorted { a, b in
            if a.isDefault { return true }
            if b.isDefault { return false }
            return a.createdAt < b.createdAt
        }
    }

    // Agent artifacts (alias for taskArtifacts)
    var agentArtifacts: [String: [DBArtifact]] {
        taskArtifacts
    }

    // MARK: - Claude Session Notifications

    /// Notify the agent session about a UI change
    func notifySessionOfChange(message: String, taskId: String? = nil) {
        guard let projectId = currentProjectId else { return }
        let manager = ClaudeCodeManager.shared
        let sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)

        if let session = manager.sessions[sessionId] {
            session.sendLine("")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                session.sendLine("⚡️ UI UPDATE: \(message)")
            }
        }
    }
    
    /// Notify about task status changes (called from UI interactions)
    func notifyTaskChange(_ taskId: String, change: String) {
        notifySessionOfChange(message: change, taskId: taskId)
    }
    
    /// Notify about criterion changes
    func notifyCriterionChange(_ criterionId: String, change: String) {
        // Find which task this criterion belongs to
        do {
            let taskId = try db.read { db in
                try DBCriterion.fetchOne(db, key: criterionId)?.taskId
            }
            if let taskId = taskId {
                notifySessionOfChange(message: change, taskId: taskId)
            }
        } catch {
            print("Failed to find criterion task: \(error)")
        }
    }

    /// Send a message to the agent session (for programmatic messages like "start task")
    func sendMessageToAgent(_ message: String) {
        guard let projectId = currentProjectId else { return }

        // Add to chat history
        addMessage(role: "user", text: message, persona: "agent", toAgentId: nil)

        // Send to agent session
        let manager = ClaudeCodeManager.shared
        let sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)

        if let session = manager.sessions[sessionId] {
            session.sendLine(message)

            // Set typing indicator
            MCPServer.shared.typingIndicators[sessionId] = true
        }
    }

    func loadDeliverables() {
        guard let pm = projectManager else {
            deliverables = []
            return
        }
        do {
            deliverables = try db.read { db in
                try DBArtifact
                    .filter(Column("taskId") == pm.id && Column("description") == "deliverable")
                    .order(Column("order"))
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load deliverables: \(error)")
        }
    }
    
    // Messages for the current agent's conversation (from cache)

    var messages: [DBMessage] {
        guard let agentId = currentAgentId else { return [] }
        return agentMessages[agentId] ?? []
    }

    // Get General task ID for current project (replaces projectManagerTaskId)
    var generalTaskId: String? {
        tasks.first(where: { $0.isProjectManager })?.id
    }

    // Alias for backwards compatibility
    var projectManagerTaskId: String? {
        generalTaskId
    }

    // Get Project Manager task ID for any project (DB lookup, safe across project switches)
    func projectManagerTaskId(forProjectId projectId: String) -> String? {
        try? db.read { db in
            try DBTask
                .filter(Column("projectId") == projectId && Column("isProjectManager") == true)
                .fetchOne(db)
        }?.id
    }
    
    private let db = DatabaseManager.shared
    
    private init() {
        loadProjects()
        loadAppState()
    }
    
    // MARK: - Projects
    
    func loadProjects() {
        do {
            projects = try db.read { db in
                try DBProject.order(Column("order")).fetchAll(db)
            }
        } catch {
            print("Failed to load projects: \(error)")
        }
    }
    
    func createProject(name: String) -> DBProject {
        let project = DBProject(name: name, order: projects.count)
        do {
            try db.write { db in
                try project.insert(db)

                // Create the General task for this project (replaces PM task)

                var general = DBTask(projectId: project.id, title: "General", isProjectManager: true)
                general.status = "running"
                try general.insert(db)
            }

            loadProjects()
            selectProject(project.id)

            // Auto-start Agent session after UI settles

            let projectCopy = project
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startSessionsForProject(projectCopy)
            }
        } catch {
            print("Failed to create project: \(error)")
        }
        return project
    }

    func startSessionsForProject(_ project: DBProject) {
        let manager = ClaudeCodeManager.shared
        let projectPath = project.localPath.isEmpty ? nil : project.localPath

        // Start Agent session

        let agentSessionId = ClaudeCodeManager.agentSessionId(projectId: project.id)
        if manager.sessions[agentSessionId] == nil {
            let session = manager.getOrCreateSession(
                id: agentSessionId,
                workingDirectory: projectPath,
                persona: .agent,
                projectId: project.id
            )
            session.start()
            print("✓ Started Agent session for project: \(project.name)")
        }
    }

    func deleteProject(_ projectId: String) {
        do {
            try db.write { db in
                try DBProject.deleteOne(db, key: projectId)
            }
            loadProjects()
            if currentProjectId == projectId {
                currentProjectId = projects.first?.id
                loadTasks()
            }
        } catch {
            print("Failed to delete project: \(error)")
        }
    }
    
    func renameProject(_ projectId: String, to name: String) {
        do {
            try db.write { db in
                if var project = try DBProject.fetchOne(db, key: projectId) {
                    project.name = name
                    try project.update(db)
                }
            }
            loadProjects()
        } catch {
            print("Failed to rename project: \(error)")
        }
    }
    
    func updateProjectSettings(_ projectId: String, name: String, description: String, sourceUrl: String, localPath: String) {
        do {
            try db.write { db in
                if var project = try DBProject.fetchOne(db, key: projectId) {
                    project.name = name
                    project.description = description
                    project.sourceUrl = sourceUrl
                    project.localPath = localPath
                    try project.update(db)
                }
            }
            loadProjects()
        } catch {
            print("Failed to update project settings: \(error)")
        }
    }
    
    func selectProject(_ projectId: String) {
        currentProjectId = projectId
        saveAppState()
        loadTasks()
        loadFileClaims()

        // Auto-select Project Manager

        if let manager = tasks.first(where: { $0.isProjectManager }) {
            selectTask(manager.id)
        }
    }

    func moveProjectUp(_ projectId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }), index > 0 else { return }
        swapProjectOrder(index, index - 1)
    }

    func moveProjectDown(_ projectId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }), index < projects.count - 1 else { return }
        swapProjectOrder(index, index + 1)
    }

    private func swapProjectOrder(_ indexA: Int, _ indexB: Int) {
        let projectA = projects[indexA]
        let projectB = projects[indexB]

        do {
            try db.write { db in
                try db.execute(sql: "UPDATE project SET \"order\" = ? WHERE id = ?", arguments: [indexB, projectA.id])
                try db.execute(sql: "UPDATE project SET \"order\" = ? WHERE id = ?", arguments: [indexA, projectB.id])
            }
            loadProjects()
        } catch {
            print("Failed to swap project order: \(error)")
        }
    }

    func moveAgentUp(_ agentId: String) {
        let nonDefault = agents.filter { !$0.isDefault }
        guard let index = nonDefault.firstIndex(where: { $0.id == agentId }), index > 0 else { return }
        swapAgentOrder(nonDefault[index], nonDefault[index - 1])
    }

    func moveAgentDown(_ agentId: String) {
        let nonDefault = agents.filter { !$0.isDefault }
        guard let index = nonDefault.firstIndex(where: { $0.id == agentId }), index < nonDefault.count - 1 else { return }
        swapAgentOrder(nonDefault[index], nonDefault[index + 1])
    }

    private func swapAgentOrder(_ agentA: DBAgent, _ agentB: DBAgent) {

        // Swap createdAt timestamps to change order

        let dateA = agentA.createdAt
        let dateB = agentB.createdAt

        do {
            try db.write { db in
                try db.execute(sql: "UPDATE task SET createdAt = ? WHERE id = ?", arguments: [dateB, agentA.id])
                try db.execute(sql: "UPDATE task SET createdAt = ? WHERE id = ?", arguments: [dateA, agentB.id])
            }
            loadTasks()
        } catch {
            print("Failed to swap agent order: \(error)")
        }
    }

    // MARK: - Artifact Reordering

    func moveArtifactUp(_ artifactId: String, agentId: String) {
        guard let artifacts = agentArtifacts[agentId] else { return }
        guard let index = artifacts.firstIndex(where: { $0.id == artifactId }), index > 0 else { return }
        swapArtifactOrder(artifacts[index], artifacts[index - 1])
    }

    func moveArtifactDown(_ artifactId: String, agentId: String) {
        guard let artifacts = agentArtifacts[agentId] else { return }
        guard let index = artifacts.firstIndex(where: { $0.id == artifactId }), index < artifacts.count - 1 else { return }
        swapArtifactOrder(artifacts[index], artifacts[index + 1])
    }

    private func swapArtifactOrder(_ artifactA: DBArtifact, _ artifactB: DBArtifact) {

        // Swap order values

        let orderA = artifactA.order
        let orderB = artifactB.order

        do {
            try db.write { db in
                try db.execute(sql: "UPDATE artifact SET \"order\" = ? WHERE id = ?", arguments: [orderB, artifactA.id])
                try db.execute(sql: "UPDATE artifact SET \"order\" = ? WHERE id = ?", arguments: [orderA, artifactB.id])
            }
            loadAllTaskArtifacts()
        } catch {
            print("Failed to swap artifact order: \(error)")
        }
    }

    // MARK: - Tasks
    
    func loadTasks() {
        guard let projectId = currentProjectId else {
            tasks = []
            agentMessages = [:]
            return
        }

        do {
            tasks = try db.read { db in
                try DBTask
                    .filter(Column("projectId") == projectId)
                    .fetchAll(db)
            }
            loadAllTaskArtifacts()
            loadAllTaskCriteria()
            loadChatMessages()
            loadEngineerCriteria()
            loadDeliverables()
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }
    
    var unfinishedTasks: [DBTask] {
        tasks.filter { !$0.isFinished && !$0.isProjectManager }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    var finishedTasks: [DBTask] {
        tasks.filter { $0.isFinished && !$0.isProjectManager }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }
    
    var projectManager: DBTask? {
        tasks.first { $0.isProjectManager }
    }
    
    func createTask(title: String) -> DBTask {
        guard let projectId = currentProjectId else {
            fatalError("No project selected")
        }

        let task = DBTask(projectId: projectId, title: title)
        do {
            try db.write { db in
                try task.insert(db)
            }

            loadTasks()
            selectTask(task.id)
        } catch {
            print("Failed to create task: \(error)")
        }
        return task
    }

    /// Create a task with full details (for MCP/CLI)
    @discardableResult
    func createTask(projectId: String, title: String, description: String, criteria: [String]) -> String {
        var task = DBTask(projectId: projectId, title: title)
        task.description = description

        do {
            try db.write { db in
                try task.insert(db)

                // Add criteria

                for (index, text) in criteria.enumerated() {
                    let criterion = DBCriterion(taskId: task.id, text: text, order: index)
                    try criterion.insert(db)
                }
            }

            loadTasks()
            loadTaskData()

            // Notify relevant Claude session about new task

            notifySessionOfChange(message: "New task created: \"\(title)\"")

        } catch {
            print("Failed to create task: \(error)")
        }
        return task.id
    }

    
    /// Update task with optional fields (for MCP/CLI)
    func updateTask(_ taskId: String, title: String?, description: String?, status: String?) {
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    if let title = title { task.title = title }
                    if let description = description { task.description = description }
                    if let status = status { task.status = status }
                    try task.update(db)
                }
            }
            loadTasks()
            loadTaskData()
        } catch {
            print("Failed to update task: \(error)")
        }
    }
    
    func updateTask(_ task: DBTask) {
        do {
            try db.write { db in
                try task.update(db)
            }
            loadTasks()
            if currentTaskId == task.id {
                // Refresh current task data
                loadTaskData()
            }
        } catch {
            print("Failed to update task: \(error)")
        }
    }
    
    func deleteTask(_ taskId: String) {
        do {
            try db.write { db in
                try DBTask.deleteOne(db, key: taskId)
            }
            loadTasks()
            if currentTaskId == taskId {
                currentTaskId = projectManager?.id
                loadTaskData()
            }
        } catch {
            print("Failed to delete task: \(error)")
        }
    }
    
    func selectTask(_ taskId: String) {
        currentTaskId = taskId

        // Use cached data - no DB reads needed
        // criteria and artifacts are now computed properties reading from taskCriteria/taskArtifacts
    }

    // MARK: - Agent Functions (aliases for task functions)

    func selectAgent(_ agentId: String) {
        selectTask(agentId)

        // Messages are already in cache (agentMessages) - instant switch
    }

    /// Add a new agent to the current project
    @discardableResult
    func addAgent() -> DBAgent {
        guard let projectId = currentProjectId else {
            fatalError("No project selected")
        }

        // Pick a random name that's not already used in this project

        let usedNames = Set(tasks.filter { !$0.isDefault }.map { $0.title })
        let availableNames = agentNames.filter { !usedNames.contains($0) }
        let agentName: String

        if let randomName = availableNames.randomElement() {
            agentName = randomName
        } else {
            // Fallback if all 100 names are used
            agentName = "Agent \(tasks.count + 1)"
        }

        let agent = DBTask(projectId: projectId, title: agentName)
        do {
            try db.write { db in
                try agent.insert(db)
            }
            loadTasks()
            selectAgent(agent.id)

            // Start a Claude session for this agent
            startAgentSession(agentId: agent.id)
        } catch {
            print("Failed to add agent: \(error)")
        }
        return agent
    }

    /// Rename an agent
    func renameAgent(_ agentId: String, name: String) {
        do {
            try db.write { db in
                if var agent = try DBTask.fetchOne(db, key: agentId) {
                    agent.title = name
                    try agent.update(db)
                }
            }
            loadTasks()
        } catch {
            print("Failed to rename agent: \(error)")
        }
    }

    /// Delete an agent (cannot delete default agent)
    func deleteAgent(_ agentId: String) {
        guard let agent = tasks.first(where: { $0.id == agentId }),
              !agent.isDefault else {
            print("Cannot delete default agent")
            return
        }

        // Stop the agent's session
        stopAgentSession(agentId: agentId)

        do {
            try db.write { db in
                try DBTask.deleteOne(db, key: agentId)
            }
            loadTasks()
            if currentAgentId == agentId {
                currentAgentId = agents.first?.id
            }
        } catch {
            print("Failed to delete agent: \(error)")
        }
    }

    /// Start a Claude session for an agent
    func startAgentSession(agentId: String) {
        guard let projectId = currentProjectId,
              let project = projects.first(where: { $0.id == projectId }),
              let agent = tasks.first(where: { $0.id == agentId }) else { return }

        let manager = ClaudeCodeManager.shared
        let sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agentId)
        let workingDir = project.localPath.isEmpty ? nil : project.localPath

        if manager.sessions[sessionId] == nil {
            let session = manager.getOrCreateSession(
                id: sessionId,
                workingDirectory: workingDir,
                persona: .agent,
                projectId: projectId,
                taskId: agentId,
                taskTitle: agent.title
            )
            session.start()
        } else if manager.sessions[sessionId]?.isRunning == false {
            manager.sessions[sessionId]?.start()
        }
    }

    /// Stop an agent's Claude session
    func stopAgentSession(agentId: String) {
        guard let projectId = currentProjectId else { return }
        let manager = ClaudeCodeManager.shared
        let sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agentId)
        manager.removeSession(id: sessionId)
    }

    func updateTaskStatus(_ taskId: String, status: String) {
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    task.status = status
                    try task.update(db)
                }
            }
            loadTasks()
        } catch {
            print("Failed to update task status: \(error)")
        }
    }
    
    func finishTask(_ taskId: String) {
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    task.isFinished = true
                    task.status = "completed"
                    task.completedAt = Date()
                    try task.update(db)
                }
            }
            loadTasks()
        } catch {
            print("Failed to finish task: \(error)")
        }
    }

    /// Mark all criteria as verified and finish the task (user-initiated "Done" button)
    func markTaskDone(_ taskId: String) {
        do {

            // Mark all criteria as verified
            try db.write { db in
                try DBCriterion
                    .filter(Column("taskId") == taskId && Column("isValidated") == false)
                    .updateAll(db, Column("isValidated").set(to: true))
            }

            // Reload criteria
            loadTaskCriteria()

            // Finish the task
            finishTask(taskId)
        } catch {
            print("Failed to mark task done: \(error)")
        }
    }

    /// Undo finishing a task - move it back to active
    func undoFinishTask(_ taskId: String) {
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    task.isFinished = false
                    task.status = "inactive"
                    task.completedAt = nil
                    try task.update(db)
                }
            }
            loadTasks()
        } catch {
            print("Failed to undo finish task: \(error)")
        }
    }

    func startTask(_ taskId: String) {
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    task.status = "running"
                    task.startedAt = Date()
                    try task.update(db)
                }
            }
            loadTasks()
            
            // Spawn the executor agent
            spawnTaskExecutor(taskId)
        } catch {
            print("Failed to start task: \(error)")
        }
    }
    
    // MARK: - Task Executor
    
    private let gatewayToken = "04ffa0dab64b10d0d0700f43fb8751d5aa6a1f63a9dacf24a6ab3a550a41928c"
    private var activeExecutorTask: Task<Void, Never>?
    
    func spawnTaskExecutor(_ taskId: String) {
        // Cancel any existing executor
        activeExecutorTask?.cancel()
        
        // Get the task details
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        
        // Get project info
        guard let project = projects.first(where: { $0.id == currentProjectId }) else { return }
        
        // Get criteria for the task
        let taskCriteria: [DBCriterion]
        do {
            taskCriteria = try db.read { db in
                try DBCriterion.filter(Column("taskId") == taskId).order(Column("order")).fetchAll(db)
            }
        } catch {
            taskCriteria = []
        }
        
        // Build the prompt
        let autoCriteria = taskCriteria.filter { !$0.isHumanValidated }.map { "- [ ] \($0.text) [id: \($0.id)]" }.joined(separator: "\n")
        let humanCriteria = taskCriteria.filter { $0.isHumanValidated }.map { "- [ ] \($0.text) [id: \($0.id)] (human-validated)" }.joined(separator: "\n")
        
        let prompt = """
        # Task: \(task.title)
        
        ## Project Context
        Project: \(project.name)
        \(project.localPath.isEmpty ? "" : "Path: \(project.localPath)\n")\(project.sourceUrl.isEmpty ? "" : "Source: \(project.sourceUrl)\n")
        ## Description
        \(task.description.isEmpty ? "(No description provided)" : task.description)
        
        ## Success Criteria
        \(autoCriteria.isEmpty && humanCriteria.isEmpty ? "None specified" : "")
        \(autoCriteria.isEmpty ? "" : "### Auto-Verified (you can validate these)\n\(autoCriteria)\n")
        \(humanCriteria.isEmpty ? "" : "### Human-Validated (user must validate)\n\(humanCriteria)")
        
        ## Your Skills
        
        LIMITATIONS: You can ONLY validate auto-criteria and manage artifacts. You CANNOT edit the task itself.
        
        ### Logging (update UI with progress)
        [[skill:add_log|type=progress|message=Working on X...]]
        [[skill:add_log|type=info|message=Found something...]]
        [[skill:add_log|type=success|message=Completed Y]]
        [[skill:add_log|type=error|message=Issue with Z]]
        
        ### Criteria Validation (auto-verified ONLY)
        [[skill:validate_criterion|criterion_id=CRITERION_ID]]
        [[skill:unvalidate_criterion|criterion_id=CRITERION_ID]]
        
        ### Task Artifacts (attach results to this task)
        [[skill:add_task_artifact|type=markdown|label=Results|content=...]]
        [[skill:update_task_artifact|artifact_id=ID|content=new content]]
        [[skill:delete_task_artifact|artifact_id=ID]]
        
        ### Project Deliverables (project-level outputs)
        [[skill:add_deliverable|type=markdown|label=Name|content=...]]
        [[skill:delete_deliverable|artifact_id=ID]]
        
        ## Instructions
        Execute this task methodically. Log your progress. Validate criteria as you complete them.
        Add artifacts with your results. Begin now.
        """
        
        // Set thinking state
        thinkingTaskId = taskId
        
        // Add initial log
        addTaskLog(taskId: taskId, type: "info", message: "Starting executor...")
        
        // Spawn async task
        activeExecutorTask = Task {
            await callExecutorAPI(taskId: taskId, prompt: prompt)
        }
    }
    
    func stopTaskExecutor() {
        activeExecutorTask?.cancel()
        activeExecutorTask = nil
        thinkingTaskId = nil
    }
    
    func sendFollowUp(taskId: String, message: String) {
        // Log the follow-up
        addTaskLog(taskId: taskId, type: "query", message: "Follow-up", details: message)
        
        // Build follow-up prompt
        let prompt = """
        ## Follow-Up Instructions from User
        
        \(message)
        
        Continue working on the task with these additional instructions.
        """
        
        // Cancel current executor and restart with follow-up
        activeExecutorTask?.cancel()
        thinkingTaskId = taskId
        
        activeExecutorTask = Task {
            await callExecutorAPI(taskId: taskId, prompt: prompt)
        }
    }
    
    private func addTaskLog(taskId: String, type: String, message: String, details: String? = nil) {
        let log = DBTaskLog(taskId: taskId, type: type, message: message, details: details)
        do {
            try db.write { db in
                try log.insert(db)
            }
            loadTaskData()
        } catch {
            print("Failed to add task log: \(error)")
        }
    }
    
    private func callExecutorAPI(taskId: String, prompt: String) async {
        let gatewayURL = URL(string: "http://127.0.0.1:18789/v1/chat/completions")!
        var request = URLRequest(url: gatewayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("task-executor:\(taskId)", forHTTPHeaderField: "x-openclaw-agent-id")
        request.timeoutInterval = 600
        
        // Build conversation history from task logs
        var messages: [[String: String]] = []
        
        // Get task logs for history (query = user, response = assistant)
        let taskLogs: [DBTaskLog] = (try? await MainActor.run {
            try db.read { db in
                try DBTaskLog.filter(Column("taskId") == taskId)
                    .order(Column("createdAt"))
                    .fetchAll(db)
            }
        }) ?? []
        
        for log in taskLogs {
            if log.type == "query", let details = log.details {
                // User follow-up question
                messages.append(["role": "user", "content": details])
            } else if log.type == "response", let details = log.details {
                // Executor response
                messages.append(["role": "assistant", "content": details])
            }
        }
        
        // Add current prompt
        messages.append(["role": "user", "content": prompt])
        
        let body: [String: Any] = [
            "model": "anthropic/claude-sonnet-4-20250514",
            "messages": messages,
            "stream": true
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var buffer = ""
            
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                
                // Parse SSE format
                if line.hasPrefix("data: ") {
                    let jsonStr = String(line.dropFirst(6))
                    if jsonStr == "[DONE]" {
                        await MainActor.run {
                            addTaskLog(taskId: taskId, type: "info", message: "Executor finished")
                            thinkingTaskId = nil
                        }
                        break
                    }
                    
                    guard let data = jsonStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any] else {
                        continue
                    }
                    
                    if let content = delta["content"] as? String {
                        buffer += content
                        
                        // Check for skill calls in buffer and execute them
                        await MainActor.run {
                            parseAndExecuteSkills(from: &buffer, taskId: taskId)
                        }
                    }
                }
            }
            
            // Process any remaining buffer
            if !buffer.isEmpty {
                await MainActor.run {
                    parseAndExecuteSkills(from: &buffer, taskId: taskId)
                    if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        addTaskLog(taskId: taskId, type: "response", message: "Output", details: buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                addTaskLog(taskId: taskId, type: "error", message: "Executor error: \(error.localizedDescription)")
                thinkingTaskId = nil
            }
        }
    }
    
    private func parseAndExecuteSkills(from buffer: inout String, taskId: String) {
        let pattern = #"\[\[skill:(\w+)\|([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsBuffer = buffer as NSString
        let matches = regex.matches(in: buffer, options: [], range: NSRange(location: 0, length: nsBuffer.length))
        
        var rangesToRemove: [NSRange] = []
        
        for match in matches {
            guard let skillRange = Range(match.range(at: 1), in: buffer),
                  let paramsRange = Range(match.range(at: 2), in: buffer) else {
                continue
            }
            
            let skillName = String(buffer[skillRange])
            let paramsStr = String(buffer[paramsRange])
            
            // Parse params
            var params: [String: Any] = [:]
            for part in paramsStr.split(separator: "|") {
                let kv = part.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    params[String(kv[0])] = String(kv[1])
                }
            }
            
            // Add task_id if not present
            if params["task_id"] == nil {
                params["task_id"] = taskId
            }
            
            // Execute the skill
            executeSkill(skillName, params: params)
            
            rangesToRemove.append(match.range)
        }
        
        // Remove executed skills from buffer (in reverse order to preserve indices)
        for range in rangesToRemove.reversed() {
            if let swiftRange = Range(range, in: buffer) {
                buffer.removeSubrange(swiftRange)
            }
        }
    }
    
    func pauseTask(_ taskId: String) {
        // Stop the executor if running
        if thinkingTaskId == taskId {
            stopTaskExecutor()
            addTaskLog(taskId: taskId, type: "info", message: "Executor paused")
        }
        
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    task.status = "paused"
                    try task.update(db)
                }
            }
            loadTasks()
        } catch {
            print("Failed to pause task: \(error)")
        }
    }
    
    func restartTask(_ taskId: String) {
        // Stop executor if running
        if thinkingTaskId == taskId {
            stopTaskExecutor()
        }
        
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    task.status = "inactive"
                    task.isFinished = false
                    task.startedAt = nil
                    task.completedAt = nil
                    try task.update(db)
                }
                // Clear logs for this task
                try DBTaskLog.filter(Column("taskId") == taskId).deleteAll(db)
                // Reset criteria validation
                try db.execute(sql: "UPDATE criterion SET isValidated = 0 WHERE taskId = ?", arguments: [taskId])
            }
            loadTasks()
            loadTaskData()
        } catch {
            print("Failed to restart task: \(error)")
        }
    }
    
    func clearContext() {
        guard let projectId = currentProjectId,
              let agentId = currentAgentId,
              let agent = agents.first(where: { $0.id == agentId }),
              let project = projects.first(where: { $0.id == projectId }) else { return }

        let manager = ClaudeCodeManager.shared
        let sessionId: String
        if agent.isDefault {
            sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)
        } else {
            sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agentId)
        }

        // Clear typing indicators

        MCPServer.shared.setTyping(sessionId: sessionId, typing: false)

        // Get or create session and force restart it

        let workingDir = project.localPath.isEmpty ? nil : project.localPath
        let session = manager.getOrCreateSession(
            id: sessionId,
            workingDirectory: workingDir,
            persona: .agent,
            projectId: projectId,
            taskId: agent.isDefault ? nil : agent.id,
            taskTitle: agent.isDefault ? nil : agent.title
        )

        // Force restart on background thread to avoid blocking UI

        DispatchQueue.global(qos: .userInitiated).async {
            session.forceRestart()
        }

        // Add a system message so the user sees the clear in chat

        addMessage(role: "system", text: "Context cleared — session restarted", toAgentId: currentAgentId)
    }

    func clearMessageHistory() {
        guard let agentId = currentAgentId else { return }

        // Delete messages for this agent from database

        do {
            try db.write { db in
                try db.execute(sql: "DELETE FROM message WHERE taskId = ?", arguments: [agentId])
            }

            // Clear from memory

            agentMessages[agentId] = []
        } catch {
            print("Failed to clear message history: \(error)")
        }
    }

    func clearAllMessageHistory() {
        guard let projectId = currentProjectId else { return }

        // Get all agents for this project

        let projectAgents = agents.filter { $0.projectId == projectId }

        do {
            try db.write { db in
                for agent in projectAgents {
                    try db.execute(sql: "DELETE FROM message WHERE taskId = ?", arguments: [agent.id])
                }
            }

            // Clear from memory

            for agent in projectAgents {
                agentMessages[agent.id] = []
            }
        } catch {
            print("Failed to clear all message history: \(error)")
        }
    }

    func clearAllContext() {
        guard let projectId = currentProjectId,
              let project = projects.first(where: { $0.id == projectId }) else { return }

        let manager = ClaudeCodeManager.shared
        let projectAgents = agents.filter { $0.projectId == projectId }

        for agent in projectAgents {
            let sessionId: String
            if agent.isDefault {
                sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)
            } else {
                sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agent.id)
            }

            // Clear typing indicators

            MCPServer.shared.setTyping(sessionId: sessionId, typing: false)

            // Get or create session and force restart it

            let workingDir = project.localPath.isEmpty ? nil : project.localPath
            let session = manager.getOrCreateSession(
                id: sessionId,
                workingDirectory: workingDir,
                persona: .agent,
                projectId: projectId,
                taskId: agent.isDefault ? nil : agent.id,
                taskTitle: agent.isDefault ? nil : agent.title
            )

            DispatchQueue.global(qos: .userInitiated).async {
                session.forceRestart()
            }

            addMessage(role: "system", text: "Context cleared — session restarted", toAgentId: agent.id)
        }
    }

    func broadcastMessage(_ message: String, toAgentIds agentIds: [String]) {
        guard let projectId = currentProjectId else { return }

        let manager = ClaudeCodeManager.shared

        for agentId in agentIds {
            guard let agent = agents.first(where: { $0.id == agentId }) else { continue }

            // Add message to agent's chat history

            addMessage(role: "user", text: message, persona: "agent", toAgentId: agentId)

            // Get or create session

            let sessionId: String
            if agent.isDefault {
                sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)
            } else {
                sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agentId)
            }

            // Send to tmux session

            if let session = manager.sessions[sessionId], session.isRunning {
                session.sendLine(message)
            } else {

                // Start session if not running

                let project = projects.first { $0.id == projectId }
                let workingDir = project?.localPath.isEmpty == false ? project?.localPath : nil

                let session = manager.getOrCreateSession(
                    id: sessionId,
                    workingDirectory: workingDir,
                    persona: .agent,
                    projectId: projectId,
                    taskId: agent.isDefault ? nil : agent.id,
                    taskTitle: agent.isDefault ? nil : agent.title
                )
                session.start()

                // Send after brief delay for session to initialize

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    session.sendLine(message)
                }
            }
        }
    }

    // MARK: - PM Skill Execution
    
    func executeSkill(_ skillName: String, params: [String: Any]) {
        print("Executing skill: \(skillName) with params: \(params)")

        switch skillName {

        // MARK: MCP Communication (real-time)
        case "send_message":
            if let message = params["message"] as? String {
                addMessage(role: "daisy", text: message, persona: "agent", toAgentId: currentAgentId)
            }

        // MARK: Project Management
        case "update_project_details":
            guard let projectId = currentProjectId,
                  var project = projects.first(where: { $0.id == projectId }) else { return }
            
            if let name = params["name"] as? String, !name.isEmpty {
                project.name = name
            }
            if let description = params["description"] as? String {
                project.description = description
            }
            if let sourceUrl = params["source_url"] as? String {
                project.sourceUrl = sourceUrl
            }
            if let localPath = params["local_path"] as? String {
                project.localPath = localPath
            }
            
            do {
                try db.write { db in
                    try project.update(db)
                }
                loadProjects()
            } catch {
                print("Failed to update project: \(error)")
            }
        
        // MARK: Criterion Management (PM)
        case "add_criterion":
            let taskId = params["task_id"] as? String ?? currentTaskId
            guard let tid = taskId else { return }
            
            if let text = params["text"] as? String, !text.isEmpty {
                let isHuman = (params["is_human"] as? String)?.lowercased() == "true"
                let previousTaskId = currentTaskId
                selectTask(tid)
                addCriterion(text: text, isHumanValidated: isHuman)
                if let prev = previousTaskId, prev != tid { selectTask(prev) }
            }
            
        case "delete_criterion":
            if let criterionId = params["criterion_id"] as? String {
                deleteCriterion(criterionId)
            }
        
        // MARK: Task Management
        case "create_task":
            if let title = params["title"] as? String {
                let task = createTask(title: title)
                if let description = params["description"] as? String {
                    updateTaskDescription(task.id, description: description)
                }
                if let autoCriteria = params["auto_criteria"] as? String {
                    for criterion in autoCriteria.split(separator: ",") {
                        addCriterion(text: String(criterion).trimmingCharacters(in: .whitespaces), isHumanValidated: false)
                    }
                }
                if let humanCriteria = params["human_criteria"] as? String {
                    for criterion in humanCriteria.split(separator: ",") {
                        addCriterion(text: String(criterion).trimmingCharacters(in: .whitespaces), isHumanValidated: true)
                    }
                }
            }
            
        case "update_task":
            if let taskId = params["task_id"] as? String {
                if let title = params["title"] as? String {
                    updateTaskTitle(taskId, title: title)
                }
                if let description = params["description"] as? String {
                    updateTaskDescription(taskId, description: description)
                }
                // Select task to add criteria to it
                let previousTaskId = currentTaskId
                selectTask(taskId)
                if let autoCriteria = params["auto_criteria"] as? String {
                    for criterion in autoCriteria.split(separator: ",") {
                        addCriterion(text: String(criterion).trimmingCharacters(in: .whitespaces), isHumanValidated: false)
                    }
                }
                if let humanCriteria = params["human_criteria"] as? String {
                    for criterion in humanCriteria.split(separator: ",") {
                        addCriterion(text: String(criterion).trimmingCharacters(in: .whitespaces), isHumanValidated: true)
                    }
                }
                if let prev = previousTaskId { selectTask(prev) }
            }
            
        case "start_task":
            if let taskId = params["task_id"] as? String {
                startTask(taskId)
            }
            
        case "pause_task":
            if let taskId = params["task_id"] as? String {
                pauseTask(taskId)
            }
            
        case "reset_task":
            if let taskId = params["task_id"] as? String {
                restartTask(taskId)
            }
            
        case "finish_task":
            if let taskId = params["task_id"] as? String {
                finishTask(taskId)
            }
            
        case "delete_task":
            if let taskId = params["task_id"] as? String {
                deleteTask(taskId)
            }
            
        case "list_tasks":
            // Returns task list as a formatted string (PM will include in response)
            let taskList = getTaskListFormatted()
            print("Task list:\n\(taskList)")
            // The response will be injected via the skill callback mechanism
            
        case "view_task":
            if let taskId = params["task_id"] as? String {
                let taskDetails = getTaskDetailsFormatted(taskId)
                print("Task details:\n\(taskDetails)")
            }
            
        // Executor skills
        case "validate_criterion":
            if let criterionId = params["criterion_id"] as? String {
                // Only allow validating auto-verified criteria, not human-validated ones
                if let criterion = getCriterion(criterionId), !criterion.isHumanValidated {
                    setCriterionValidation(criterionId, validated: true)
                } else {
                    print("Blocked: Cannot auto-validate human-validated criterion \(criterionId)")
                }
            }
            
        case "unvalidate_criterion":
            if let criterionId = params["criterion_id"] as? String {
                // Only allow unvalidating auto-verified criteria
                if let criterion = getCriterion(criterionId), !criterion.isHumanValidated {
                    setCriterionValidation(criterionId, validated: false)
                }
            }
            
        case "add_task_artifact":
            // Executor can add artifacts to tasks
            if let label = params["label"] as? String {
                let taskId = params["task_id"] as? String ?? currentTaskId ?? ""
                let artifactType = params["type"] as? String ?? "markdown"
                let content = params["content"] as? String ?? ""
                if !taskId.isEmpty {
                    addArtifact(taskId: taskId, type: artifactType, label: label, content: content, isDeliverable: false)
                }
            }
            
        case "update_artifact", "update_task_artifact", "update_deliverable":
            // Update artifact content
            if let artifactId = params["artifact_id"] as? String,
               let content = params["content"] as? String {
                updateArtifactContent(artifactId, content: content)
            }
            
        case "add_deliverable":
            // PM only - add to project deliverables
            if let artifactType = params["type"] as? String,
               let label = params["label"] as? String,
               let projectId = currentProjectId {
                let content = params["content"] as? String ?? ""
                if let pmTask = projectManager {
                    addArtifact(taskId: pmTask.id, type: artifactType, label: label, content: content, isDeliverable: true)
                }
            }
            
        case "delete_artifact", "delete_task_artifact", "delete_deliverable":
            if let artifactId = params["artifact_id"] as? String {
                deleteArtifact(artifactId)
            }
            
        case "list_task_artifacts":
            if let taskId = params["task_id"] as? String {
                let list = listTaskArtifactsFormatted(taskId)
                print("Task artifacts:\n\(list)")
            }
            
        case "delete_all_task_artifacts":
            if let taskId = params["task_id"] as? String {
                deleteAllTaskArtifacts(taskId)
            }
            
        case "list_deliverables":
            let list = listDeliverablesFormatted()
            print("Deliverables:\n\(list)")
        
        // MARK: - Criteria Skills (for Engineer)
        
        case "list_criteria":
            let taskId = params["task_id"] as? String ?? currentTaskId
            if let taskId = taskId {
                let criteriaList = listCriteriaFormatted(taskId)
                addMessage(role: "tool", text: "📋 **Agent Criteria**\n\(criteriaList)", persona: "agent", toAgentId: currentAgentId)
            }

        case "verify_criterion":
            if let criterionId = params["criterion_id"] as? String {
                verifyCriterion(criterionId)
                addMessage(role: "tool", text: "✅ Criterion marked as verified", persona: "agent", toAgentId: currentAgentId)
            }
        
        // MARK: - Typed Artifact Skills
        
        case "add_code_artifact":
            let taskId = params["task_id"] as? String ?? currentTaskId ?? ""
            let label = params["label"] as? String ?? "Code"
            let code = params["content"] as? String ?? params["code"] as? String ?? ""
            let language = params["language"] as? String ?? "plaintext"
            let isDeliverable = (params["deliverable"] as? String)?.lowercased() == "true"
            
            if !taskId.isEmpty {
                addCodeArtifact(taskId: taskId, label: label, code: code, language: language, isDeliverable: isDeliverable)
            }
        
        case "add_image_artifact":
            let taskId = params["task_id"] as? String ?? currentTaskId ?? ""
            let label = params["label"] as? String ?? "Image"
            let base64 = params["content"] as? String ?? params["base64"] as? String ?? ""
            let path = params["path"] as? String
            let isDeliverable = (params["deliverable"] as? String)?.lowercased() == "true"
            
            if !taskId.isEmpty {
                addImageArtifact(taskId: taskId, label: label, base64: base64, path: path, isDeliverable: isDeliverable)
            }
        
        case "add_csv_artifact":
            let taskId = params["task_id"] as? String ?? currentTaskId ?? ""
            let label = params["label"] as? String ?? "Data"
            let content = params["content"] as? String ?? ""
            let path = params["path"] as? String
            let maxRows = min(Int(params["max_rows"] as? String ?? "10") ?? 10, 100)
            let isDeliverable = (params["deliverable"] as? String)?.lowercased() == "true"
            
            if !taskId.isEmpty {
                addCSVArtifact(taskId: taskId, label: label, content: content, path: path, maxRows: maxRows, isDeliverable: isDeliverable)
            }
        
        case "view_artifact":
            if let artifactId = params["artifact_id"] as? String {
                let details = getArtifactDetails(artifactId)
                addMessage(role: "tool", text: details, persona: "agent")
            }

        case "get_csv_rows":
            if let artifactId = params["artifact_id"] as? String {
                let startRow = Int(params["start"] as? String ?? "0") ?? 0
                let count = min(Int(params["count"] as? String ?? "10") ?? 10, 100)
                let rows = getCSVRows(artifactId: artifactId, start: startRow, count: count)
                addMessage(role: "tool", text: rows, persona: "agent")
            }
            
        // MARK: - Proposal Skills (require user confirmation)
        case "propose_create":
            let title = params["title"] as? String ?? "Untitled Task"
            let description = params["description"] as? String ?? ""
            let autoCriteria = params["auto_criteria"] as? String ?? ""
            let humanCriteria = params["human_criteria"] as? String ?? ""
            
            var summary = "**Create Task**\n\n**Title:** \(title)"
            if !description.isEmpty { 
                summary += "\n\n**Description:** \(description)" 
            }
            if !autoCriteria.isEmpty {
                summary += "\n\n**Auto-Verified Criteria:**"
                for criterion in autoCriteria.split(separator: ",") {
                    summary += "\n• \(criterion.trimmingCharacters(in: .whitespaces))"
                }
            }
            if !humanCriteria.isEmpty {
                summary += "\n\n**Human-Validated Criteria:**"
                for criterion in humanCriteria.split(separator: ",") {
                    summary += "\n• \(criterion.trimmingCharacters(in: .whitespaces))"
                }
            }
            
            pendingProposals.append(PendingProposal(
                type: .create,
                params: params,
                summary: summary,
                taskId: currentTaskId ?? "",
                projectId: currentProjectId ?? ""
            ))
            print("Proposal created: \(summary)")
            
        case "propose_update":
            guard let taskId = params["task_id"] as? String,
                  let task = tasks.first(where: { $0.id == taskId }) else {
                print("propose_update: task not found")
                return
            }
            
            // Get existing criteria
            let existingCriteria: [DBCriterion] = (try? db.read { db in
                try DBCriterion.filter(Column("taskId") == taskId).fetchAll(db)
            }) ?? []
            let existingAuto = existingCriteria.filter { !$0.isHumanValidated }.map { $0.text }
            let existingHuman = existingCriteria.filter { $0.isHumanValidated }.map { $0.text }
            
            var summary = "**Update Task**\n"
            
            // Title diff
            if let newTitle = params["title"] as? String, !newTitle.isEmpty, newTitle != task.title {
                summary += "\n**Title:**\n~~\(task.title)~~\n\(newTitle)"
            }
            
            // Description diff
            if let newDesc = params["description"] as? String, !newDesc.isEmpty, newDesc != task.description {
                if !task.description.isEmpty {
                    summary += "\n\n**Description:**\n~~\(task.description)~~\n\(newDesc)"
                } else {
                    summary += "\n\n**Description:**\n\(newDesc)"
                }
            }
            
            // Auto-verified criteria diff
            if let autoCriteriaStr = params["auto_criteria"] as? String {
                let newAuto = autoCriteriaStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let newAutoSet = Set(newAuto)
                let existingAutoSet = Set(existingAuto)
                
                if newAutoSet != existingAutoSet || !autoCriteriaStr.isEmpty {
                    summary += "\n\n**Auto-Verified Criteria:**"
                    // Show removed (in old but not in new)
                    for criterion in existingAuto where !newAutoSet.contains(criterion) {
                        summary += "\n• ~~\(criterion)~~"
                    }
                    // Show kept (in both)
                    for criterion in newAuto where existingAutoSet.contains(criterion) {
                        summary += "\n• \(criterion)"
                    }
                    // Show added (in new but not in old)
                    for criterion in newAuto where !existingAutoSet.contains(criterion) {
                        summary += "\n• [NEW] \(criterion)"
                    }
                }
            }
            
            // Human-validated criteria diff
            if let humanCriteriaStr = params["human_criteria"] as? String {
                let newHuman = humanCriteriaStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let newHumanSet = Set(newHuman)
                let existingHumanSet = Set(existingHuman)
                
                if newHumanSet != existingHumanSet || !humanCriteriaStr.isEmpty {
                    summary += "\n\n**Human-Validated Criteria:**"
                    // Show removed
                    for criterion in existingHuman where !newHumanSet.contains(criterion) {
                        summary += "\n• ~~\(criterion)~~"
                    }
                    // Show kept
                    for criterion in newHuman where existingHumanSet.contains(criterion) {
                        summary += "\n• \(criterion)"
                    }
                    // Show added
                    for criterion in newHuman where !existingHumanSet.contains(criterion) {
                        summary += "\n• [NEW] \(criterion)"
                    }
                }
            }
            
            pendingProposals.append(PendingProposal(
                type: .update,
                params: params,
                summary: summary,
                taskId: currentTaskId ?? "",
                projectId: currentProjectId ?? ""
            ))
            print("Proposal created: \(summary)")

        case "propose_delete":
            guard let taskId = params["task_id"] as? String,
                  let task = tasks.first(where: { $0.id == taskId }) else {
                print("propose_delete: task not found")
                return
            }
            
            let summary = "**Delete Task**\n\n⚠️ **\(task.title)**\n\nThis will permanently delete the task and all its criteria, logs, and artifacts."
            
            pendingProposals.append(PendingProposal(
                type: .delete,
                params: params,
                summary: summary,
                taskId: currentTaskId ?? "",
                projectId: currentProjectId ?? ""
            ))

        case "propose_project_update":
            guard let projectId = currentProjectId,
                  let project = projects.first(where: { $0.id == projectId }) else { return }

            var changes: [String] = []

            if let newName = params["name"] as? String, !newName.isEmpty, newName != project.name {
                changes.append("Name: \(project.name) → \(newName)")
            }
            if let newDesc = params["description"] as? String, newDesc != project.description {
                changes.append("Description updated")
            }
            if let newUrl = params["source_url"] as? String, newUrl != project.sourceUrl {
                changes.append("Source URL: \(newUrl)")
            }
            if let newPath = params["local_path"] as? String, newPath != project.localPath {
                changes.append("Local Path: \(newPath)")
            }

            let summary = changes.joined(separator: " · ")
            
            pendingProposals.append(PendingProposal(
                type: .projectUpdate,
                params: params,
                summary: summary,
                taskId: currentTaskId ?? "",
                projectId: currentProjectId ?? ""
            ))

        case "propose_start":
            guard let taskId = params["task_id"] as? String,
                  let task = tasks.first(where: { $0.id == taskId }) else { return }
            
            let summary = "**Start Task**\n\n▶️ **\(task.title)**\n\nThis will start the executor agent for this task."
            
            pendingProposals.append(PendingProposal(
                type: .start,
                params: params,
                summary: summary,
                taskId: currentTaskId ?? "",
                projectId: currentProjectId ?? ""
            ))

        case "propose_finish":
            guard let taskId = params["task_id"] as? String,
                  let task = tasks.first(where: { $0.id == taskId }) else { return }
            
            let summary = "**Finish Task**\n\n✓ **\(task.title)**\n\nMark this task as complete."
            
            pendingProposals.append(PendingProposal(
                type: .finish,
                params: params,
                summary: summary,
                taskId: currentTaskId ?? "",
                projectId: currentProjectId ?? ""
            ))

        // MARK: - View Skills (read-only, returns data to agent)
        case "view_task":
            if let taskId = params["task_id"] as? String {
                let details = getTaskDetailsFormatted(taskId)
                // Add as assistant message so agent sees the result
                addMessage(role: "tool", text: "📋 **Task Details**\n\(details)", persona: "manager")
            }
        
        case "view_task_artifacts":
            if let taskId = params["task_id"] as? String {
                let list = listTaskArtifactsFormatted(taskId)
                addMessage(role: "tool", text: "📎 **Task Artifacts**\n\(list)", persona: "manager")
            }
        
        case "view_task_logs":
            if let taskId = params["task_id"] as? String {
                let logs = getTaskLogsFormatted(taskId)
                addMessage(role: "tool", text: "📝 **Task Logs**\n\(logs)", persona: "manager")
            }
            
        default:
            print("Unknown skill: \(skillName)")
        }
    }
    
    // MARK: - Proposal Confirmation
    
    func confirmProposal() {
        guard let proposal = pendingProposal else { return }

        // Capture PM task ID so the acceptance card always lands in the PM chat

        let pmTaskId = projectManagerTaskId
        let previousTaskId = currentTaskId

        var actionName = ""

        switch proposal.type {
        case .create:
            actionName = proposal.params["title"] as? String ?? "task"
            executeSkill("create_task", params: proposal.params)

            // Restore selection so UI stays on the PM chat

            if let prev = previousTaskId {
                selectTask(prev)
            }

        case .update:
            if let taskId = proposal.params["task_id"] as? String,
               let task = tasks.first(where: { $0.id == taskId }) {
                actionName = task.title
            } else {
                actionName = "task"
            }
            executeSkill("update_task", params: proposal.params)

        case .delete:
            if let taskId = proposal.params["task_id"] as? String,
               let task = tasks.first(where: { $0.id == taskId }) {
                actionName = task.title
                deleteTask(taskId)
            }

        case .projectUpdate:
            actionName = "project settings"
            executeSkill("update_project_details", params: proposal.params)

        case .start:
            if let taskId = proposal.params["task_id"] as? String,
               let task = tasks.first(where: { $0.id == taskId }) {
                actionName = task.title
                startTask(taskId)
            }

        case .finish:
            if let taskId = proposal.params["task_id"] as? String,
               let task = tasks.first(where: { $0.id == taskId }) {
                actionName = task.title
                finishTask(taskId)
            }
        }

        // Add acceptance card to the PM chat

        let typeLabel: String
        switch proposal.type {
        case .create: typeLabel = "create"
        case .update: typeLabel = "update"
        case .delete: typeLabel = "delete"
        case .projectUpdate: typeLabel = "project_update"
        case .start: typeLabel = "start"
        case .finish: typeLabel = "finish"
        }

        let cardText = "\(typeLabel)|\(actionName)|\(proposal.summary)"
        addMessage(role: "proposal_accepted", text: cardText, persona: "agent", toAgentId: currentAgentId)

        // Remove this specific proposal (by ID, not first)
        pendingProposals.removeAll { $0.id == proposal.id }
    }

    func rejectProposal(reason: String? = nil) {
        let _ = rejectProposalAndGetMessage(reason: reason)
    }
    
    func rejectProposalAndGetMessage(reason: String? = nil) -> String {
        guard let proposal = pendingProposal else { return "" }
        
        var actionName = ""
        
        switch proposal.type {
        case .create:
            actionName = proposal.params["title"] as? String ?? "task"
        case .update:
            if let taskId = proposal.params["task_id"] as? String,
               let task = tasks.first(where: { $0.id == taskId }) {
                actionName = task.title
            } else {
                actionName = "task"
            }
        case .delete:
            if let taskId = proposal.params["task_id"] as? String,
               let task = tasks.first(where: { $0.id == taskId }) {
                actionName = "delete \(task.title)"
            }
        case .projectUpdate:
            actionName = "project update"
        case .start:
            if let taskId = proposal.params["task_id"] as? String,
               let task = tasks.first(where: { $0.id == taskId }) {
                actionName = "start \(task.title)"
            }
        case .finish:
            if let taskId = proposal.params["task_id"] as? String,
               let task = tasks.first(where: { $0.id == taskId }) {
                actionName = "finish \(task.title)"
            }
        }
        
        // Build rejection message
        let message: String
        if let reason = reason, !reason.isEmpty {
            message = "✗ Rejected: \(actionName)\nReason: \(reason)"
        } else {
            message = "✗ Rejected: \(actionName)"
        }

        // Remove this specific proposal (by ID, not first)
        pendingProposals.removeAll { $0.id == proposal.id }
        return message
    }
    
    // Generate a formatted update proposal for a task
    func generateUpdateProposal(taskId: String, newTitle: String?, newDescription: String?, newAutoCriteria: String?, newHumanCriteria: String?) -> String {
        // Get the existing task
        guard let task = tasks.first(where: { $0.id == taskId }) else {
            return "Error: Task not found"
        }
        
        // Get existing criteria for this task
        let existingCriteria: [DBCriterion]
        do {
            existingCriteria = try db.read { db in
                try DBCriterion.filter(Column("taskId") == taskId).order(Column("order")).fetchAll(db)
            }
        } catch {
            existingCriteria = []
        }
        
        let existingAutoCriteria = existingCriteria.filter { !$0.isHumanValidated }
        let existingHumanCriteria = existingCriteria.filter { $0.isHumanValidated }
        
        var lines: [String] = ["---", ""]
        
        // Title section
        if let newTitle = newTitle, !newTitle.isEmpty {
            lines.append("**Title:**")
            if !task.title.isEmpty && task.title != newTitle {
                lines.append("")
                lines.append("~~\(task.title)~~")
            }
            lines.append("")
            lines.append(newTitle)
            lines.append("")
        }
        
        // Description section
        if let newDesc = newDescription {
            lines.append("**Description:**")
            if !task.description.isEmpty && task.description != newDesc {
                lines.append("")
                lines.append("~~\(task.description)~~")
            }
            lines.append("")
            lines.append(newDesc)
            lines.append("")
        }
        
        // Auto-Verified Criteria section
        let newAutoList = newAutoCriteria?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        if !newAutoList.isEmpty || !existingAutoCriteria.isEmpty {
            lines.append("**Auto-Verified Criteria:**")
            for criterion in existingAutoCriteria {
                if !newAutoList.contains(criterion.text) {
                    lines.append("- [REMOVED] ~~\(criterion.text)~~")
                } else {
                    lines.append("- \(criterion.text)")
                }
            }
            for newCrit in newAutoList {
                if !existingAutoCriteria.contains(where: { $0.text == newCrit }) {
                    lines.append("- [NEW] \(newCrit)")
                }
            }
            lines.append("")
        }
        
        // Human-Validated Criteria section
        let newHumanList = newHumanCriteria?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        if !newHumanList.isEmpty || !existingHumanCriteria.isEmpty {
            lines.append("**Human-Validated Criteria:**")
            for criterion in existingHumanCriteria {
                if !newHumanList.contains(criterion.text) {
                    lines.append("- [REMOVED] ~~\(criterion.text)~~")
                } else {
                    lines.append("- \(criterion.text)")
                }
            }
            for newCrit in newHumanList {
                if !existingHumanCriteria.contains(where: { $0.text == newCrit }) {
                    lines.append("- [NEW] \(newCrit)")
                }
            }
            lines.append("")
        }
        
        lines.append("---")
        lines.append("")
        lines.append("Apply these changes? (yes/no)")
        
        return lines.joined(separator: "\n")
    }
    
    // Generate a formatted create proposal for a new task
    func generateCreateProposal(title: String, description: String?, autoCriteria: String?, humanCriteria: String?) -> String {
        var lines: [String] = ["---", ""]
        
        // Title section
        lines.append("**Title:**")
        lines.append("")
        lines.append(title)
        lines.append("")
        
        // Description section
        if let desc = description, !desc.isEmpty {
            lines.append("**Description:**")
            lines.append("")
            lines.append(desc)
            lines.append("")
        }
        
        // Auto-Verified Criteria section
        let autoList = autoCriteria?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        if !autoList.isEmpty {
            lines.append("**Auto-Verified Criteria:**")
            for crit in autoList {
                lines.append("- \(crit)")
            }
            lines.append("")
        }
        
        // Human-Validated Criteria section
        let humanList = humanCriteria?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        if !humanList.isEmpty {
            lines.append("**Human-Validated Criteria:**")
            for crit in humanList {
                lines.append("- \(crit)")
            }
            lines.append("")
        }
        
        lines.append("---")
        lines.append("")
        lines.append("Create this task? (yes/no)")
        
        return lines.joined(separator: "\n")
    }
    
    func getCriterion(_ criterionId: String) -> DBCriterion? {
        do {
            return try db.read { db in
                try DBCriterion.fetchOne(db, key: criterionId)
            }
        } catch {
            print("Failed to get criterion: \(error)")
            return nil
        }
    }
    
    func setCriterionValidation(_ criterionId: String, validated: Bool) {
        do {
            try db.write { db in
                if var criterion = try DBCriterion.fetchOne(db, key: criterionId) {
                    criterion.isValidated = validated
                    try criterion.update(db)
                }
            }
            loadTaskData()
        } catch {
            print("Failed to update criterion validation: \(error)")
        }
    }
    
    @discardableResult
    func addArtifact(taskId: String, type: String, label: String, content: String, isDeliverable: Bool, path: String? = nil, language: String? = nil, caption: String? = nil) -> String? {
        var artifact = DBArtifact(taskId: taskId, type: type, label: label, file: content)
        artifact.description = isDeliverable ? "deliverable" : nil
        artifact.path = path
        artifact.language = language
        artifact.caption = caption
        do {
            try db.write { db in
                try artifact.insert(db)
            }
            loadTaskData()
            loadDeliverables()
            loadAllTaskArtifacts()
            loadAllTaskCriteria()
            return artifact.id
        } catch {
            print("Failed to add artifact: \(error)")
            return nil
        }
    }
    
    func updateArtifact(_ artifactId: String, content: String) {
        updateArtifactContent(artifactId, content: content)
    }
    
    func addCodeArtifact(taskId: String, label: String, code: String, language: String, isDeliverable: Bool) {
        addArtifact(taskId: taskId, type: "code", label: label, content: code, isDeliverable: isDeliverable, language: language)
    }

    func addImageArtifact(taskId: String, label: String, base64: String, path: String?, isDeliverable: Bool) {
        addArtifact(taskId: taskId, type: "image", label: label, content: base64, isDeliverable: isDeliverable, path: path)
    }

    func addCSVArtifact(taskId: String, label: String, content: String, path: String?, maxRows: Int, isDeliverable: Bool) {
        var artifact = DBArtifact(taskId: taskId, type: "csv", label: label, file: content)
        artifact.path = path
        artifact.maxRows = min(maxRows, 100)
        artifact.description = isDeliverable ? "deliverable" : nil
        do {
            try db.write { db in
                try artifact.insert(db)
            }
            loadTaskData()
            loadDeliverables()
            loadAllTaskArtifacts()
            loadAllTaskCriteria()
        } catch {
            print("Failed to add CSV artifact: \(error)")
        }
    }

    func getArtifactDetails(_ artifactId: String) -> String {
        guard let artifact = artifacts.first(where: { $0.id == artifactId }) ??
              deliverables.first(where: { $0.id == artifactId }) else {
            return "Artifact not found"
        }

        var lines: [String] = [
            "**\(artifact.label)** (\(artifact.type))",
            "ID: \(artifact.id)"
        ]

        if let lang = artifact.language {
            lines.append("Language: \(lang)")
        }
        if let path = artifact.path {
            lines.append("Path: \(path)")
        }
        if let caption = artifact.caption, !caption.isEmpty {
            lines.append("Caption: \(caption)")
        }

        switch artifact.type {
        case "code":
            lines.append("\n```\(artifact.language ?? "")")
            lines.append(artifact.file)
            lines.append("```")
        case "csv":
            lines.append("\nPreview:")
            let previewRows = getCSVPreview(artifact.file, maxRows: artifact.maxRows ?? 10)
            lines.append(previewRows)
        case "image":
            if let path = artifact.path {
                lines.append("\nImage: \(path)")
            }
        default:
            lines.append("\n\(artifact.file.prefix(500))")
        }

        return lines.joined(separator: "\n")
    }
    
    func getCSVRows(artifactId: String, start: Int, count: Int) -> String {
        guard let artifact = artifacts.first(where: { $0.id == artifactId }) ?? 
              deliverables.first(where: { $0.id == artifactId }),
              artifact.type == "csv" else {
            return "CSV artifact not found"
        }
        
        // If there's a file path, read from it; otherwise use content
        let csvContent: String
        if let path = artifact.path, !path.isEmpty {
            csvContent = readCSVFile(path: path, start: start, count: count)
        } else {
            csvContent = extractCSVRows(artifact.file, start: start, count: count)
        }
        
        return csvContent
    }
    
    private func getCSVPreview(_ content: String, maxRows: Int) -> String {
        return extractCSVRows(content, start: 0, count: maxRows)
    }
    
    private func extractCSVRows(_ content: String, start: Int, count: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        let header = lines.first ?? ""
        let dataLines = Array(lines.dropFirst())
        
        let endIndex = min(start + count, dataLines.count)
        guard start < dataLines.count else {
            return "No data at row \(start)"
        }
        
        var result = [header]
        result.append(contentsOf: dataLines[start..<endIndex])
        return result.joined(separator: "\n")
    }
    
    private func readCSVFile(path: String, start: Int, count: Int) -> String {
        guard let projectPath = getProjectPath() else {
            return "Error: No project path"
        }
        
        let fullPath = projectPath.appendingPathComponent(path)
        guard let fileHandle = FileHandle(forReadingAtPath: fullPath.path) else {
            return "Error: Cannot open file"
        }
        defer { fileHandle.closeFile() }
        
        // Read header + requested rows
        var lines: [String] = []
        var currentRow = -1  // -1 for header
        
        // Simple line-by-line reading (not optimal for huge files but works)
        if let data = fileHandle.readDataToEndOfFile() as Data?,
           let content = String(data: data, encoding: .utf8) {
            let allLines = content.components(separatedBy: .newlines)
            
            if let header = allLines.first {
                lines.append(header)
            }
            
            let dataLines = Array(allLines.dropFirst())
            let endIndex = min(start + count, dataLines.count)
            if start < dataLines.count {
                lines.append(contentsOf: dataLines[start..<endIndex])
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    // All task artifacts (for sidebar display)
    @Published var taskArtifacts: [String: [DBArtifact]] = [:]  // taskId -> artifacts
    @Published var taskCriteria: [String: [DBCriterion]] = [:]  // taskId -> criteria
    @Published var selectedArtifactId: String?
    @Published var engineerCriteria: [DBEngineerCriterion] = []  // Current project's engineer criteria
    @Published var fileClaims: [DBFileClaim] = []  // Current project's file claims

    func loadAllTaskArtifacts() {
        guard let projectId = currentProjectId else {
            taskArtifacts = [:]
            return
        }

        // Only load artifacts for agents in the current project

        let projectTaskIds = tasks.map { $0.id }

        do {
            let allArtifacts = try db.read { db in
                try DBArtifact
                    .filter(projectTaskIds.contains(Column("taskId")) && (Column("description") != "deliverable" || Column("description") == nil))
                    .order(Column("order"))
                    .fetchAll(db)
            }
            var grouped: [String: [DBArtifact]] = [:]
            for artifact in allArtifacts {
                grouped[artifact.taskId, default: []].append(artifact)
            }
            taskArtifacts = grouped
        } catch {
            print("Failed to load task artifacts: \(error)")
        }
    }
    
    func loadAllTaskCriteria() {
        guard let projectId = currentProjectId else {
            taskCriteria = [:]
            return
        }

        // Only load criteria for agents in the current project

        let projectTaskIds = tasks.map { $0.id }

        do {
            let allCriteria = try db.read { db in
                try DBCriterion
                    .filter(projectTaskIds.contains(Column("taskId")))
                    .order(Column("order"))
                    .fetchAll(db)
            }
            var grouped: [String: [DBCriterion]] = [:]
            for criterion in allCriteria {
                grouped[criterion.taskId, default: []].append(criterion)
            }
            taskCriteria = grouped
        } catch {
            print("Failed to load task criteria: \(error)")
        }
    }
    
    // MARK: - Engineer Criteria (project-scoped, independent of tasks)
    
    func loadEngineerCriteria() {
        guard let projectId = currentProjectId else {
            engineerCriteria = []
            return
        }
        do {
            engineerCriteria = try db.read { db in
                try DBEngineerCriterion
                    .filter(Column("projectId") == projectId)
                    .order(Column("order"))
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load engineer criteria: \(error)")
        }
    }
    
    @discardableResult
    func addEngineerCriterion(text: String, isHumanValidated: Bool = false, fromUI: Bool = false) -> String {
        guard let projectId = currentProjectId else { return "" }
        let criterion = DBEngineerCriterion(
            projectId: projectId,
            text: text,
            isHumanValidated: isHumanValidated,
            order: engineerCriteria.count
        )
        do {
            try db.write { db in
                try criterion.insert(db)
            }
            loadEngineerCriteria()
        } catch {
            print("Failed to add engineer criterion: \(error)")
        }
        return criterion.id
    }
    
    func toggleEngineerCriterion(_ criterionId: String, fromUI: Bool = false) {
        var criterionText = ""
        var newState = false
        do {
            try db.write { db in
                if var criterion = try DBEngineerCriterion.fetchOne(db, key: criterionId) {
                    criterion.isCompleted.toggle()
                    criterionText = criterion.text
                    newState = criterion.isCompleted
                    if criterion.isCompleted {
                        criterion.completedAt = Date()
                    } else {
                        criterion.completedAt = nil
                    }
                    try criterion.update(db)
                }
            }
            loadEngineerCriteria()
        } catch {
            print("Failed to toggle engineer criterion: \(error)")
        }
    }
    
    func deleteEngineerCriterion(_ criterionId: String, fromUI: Bool = false) {

        // Get the criterion text before deleting for notification

        var criterionText = ""
        if fromUI {
            criterionText = engineerCriteria.first(where: { $0.id == criterionId })?.text ?? ""
        }

        do {
            try db.write { db in
                try DBEngineerCriterion.deleteOne(db, key: criterionId)
            }
            loadEngineerCriteria()
        } catch {
            print("Failed to delete engineer criterion: \(error)")
        }
    }

    func updateEngineerCriterion(_ criterionId: String, text: String, fromUI: Bool = false) {
        do {
            try db.write { db in
                if var criterion = try DBEngineerCriterion.fetchOne(db, key: criterionId) {
                    criterion.text = text
                    try criterion.update(db)
                }
            }
            loadEngineerCriteria()
        } catch {
            print("Failed to update engineer criterion: \(error)")
        }
    }

    func clearCompletedEngineerCriteria() {
        guard let projectId = currentProjectId else { return }
        do {
            try db.write { db in
                try DBEngineerCriterion
                    .filter(Column("projectId") == projectId && Column("isCompleted") == true)
                    .deleteAll(db)
            }
            loadEngineerCriteria()
        } catch {
            print("Failed to clear completed criteria: \(error)")
        }
    }
    
    func notifyAgentSession(message: String) {
        guard let projectId = currentProjectId else { return }
        let manager = ClaudeCodeManager.shared
        let sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)

        if let session = manager.sessions[sessionId] {

            // Set typing indicator before sending notification

            MCPServer.shared.setTyping(sessionId: sessionId, typing: true)

            session.sendLine("")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                session.sendLine("⚡️ UI UPDATE: \(message)")
            }
        }
    }
    
    func selectArtifact(_ artifactId: String?) {
        selectedArtifactId = artifactId
    }
    
    func deleteArtifact(_ artifactId: String) {
        do {
            try db.write { db in
                try DBArtifact.deleteOne(db, key: artifactId)
            }
            if selectedArtifactId == artifactId {
                selectedArtifactId = nil
            }
            loadTaskData()
            loadDeliverables()
            loadAllTaskArtifacts()
            loadAllTaskCriteria()
        } catch {
            print("Failed to delete artifact: \(error)")
        }
    }
    
    func deleteAllTaskArtifacts(_ taskId: String) {
        do {
            try db.write { db in
                try DBArtifact.filter(Column("taskId") == taskId && (Column("description") != "deliverable" || Column("description") == nil)).deleteAll(db)
            }
            if let currentTask = currentTaskId, currentTask == taskId {
                selectedArtifactId = nil
            }
            loadTaskData()
            loadAllTaskArtifacts()
            loadAllTaskCriteria()
        } catch {
            print("Failed to delete all task artifacts: \(error)")
        }
    }

    // -------------------------------------------------------------------------------------
    // ---------------------------------- File Claims --------------------------------------
    // -------------------------------------------------------------------------------------

    // Claims auto-expire after this many seconds (default 2 minutes)

    static let claimTTLSeconds: TimeInterval = 120

    func loadFileClaims() {
        guard let projectId = currentProjectId else {
            fileClaims = []
            return
        }

        // Clean up expired claims first

        cleanupExpiredClaims()

        do {
            fileClaims = try db.read { db in
                try DBFileClaim.filter(Column("projectId") == projectId).fetchAll(db)
            }
        } catch {
            print("Failed to load file claims: \(error)")
            fileClaims = []
        }
    }

    func cleanupExpiredClaims() {
        let cutoff = Date().addingTimeInterval(-Self.claimTTLSeconds)
        do {
            try db.write { db in
                try DBFileClaim.filter(Column("claimedAt") < cutoff).deleteAll(db)
            }
        } catch {
            print("Failed to cleanup expired claims: \(error)")
        }
    }

    /// Attempt to claim files for an agent. Returns (success, error message).
    /// If any file is already claimed by another agent, none are claimed.
    /// Claims auto-expire after claimTTLSeconds.

    func claimFiles(_ filePaths: [String], agentId: String) -> (success: Bool, message: String) {
        guard let projectId = currentProjectId else {
            return (false, "No project selected")
        }

        // Clean up expired claims first

        cleanupExpiredClaims()
        loadFileClaims()

        // Check for conflicts

        let conflicts = fileClaims.filter { claim in
            filePaths.contains(claim.filePath) && claim.agentId != agentId
        }

        if !conflicts.isEmpty {
            let conflictInfo = conflicts.map { claim -> String in
                let agentName = agents.first { $0.id == claim.agentId }?.title ?? claim.agentId
                let remaining = Int(Self.claimTTLSeconds - Date().timeIntervalSince(claim.claimedAt))
                return "  - \(claim.filePath) (claimed by \(agentName), expires in \(remaining)s)"
            }.joined(separator: "\n")
            return (false, "Cannot claim files — already claimed by another agent:\n\(conflictInfo)\n\nRetry in a few seconds or use wait_for_claim.")
        }

        // Claim all files (or refresh existing claims by this agent)

        do {
            try db.write { db in
                for path in filePaths {
                    let existing = try DBFileClaim
                        .filter(Column("projectId") == projectId && Column("filePath") == path)
                        .fetchOne(db)

                    if var claim = existing, claim.agentId == agentId {

                        // Refresh the claim timestamp

                        claim.claimedAt = Date()
                        try claim.update(db)
                    } else if existing == nil {
                        let claim = DBFileClaim(projectId: projectId, agentId: agentId, filePath: path)
                        try claim.insert(db)
                    }
                }
            }
            loadFileClaims()
            return (true, "Claimed \(filePaths.count) file(s) for \(Int(Self.claimTTLSeconds))s")
        } catch {
            return (false, "Failed to claim files: \(error)")
        }
    }

    /// Release claims on files for an agent

    func releaseFiles(_ filePaths: [String], agentId: String) -> (success: Bool, message: String) {
        guard let projectId = currentProjectId else {
            return (false, "No project selected")
        }

        do {
            try db.write { db in
                try DBFileClaim
                    .filter(Column("projectId") == projectId && Column("agentId") == agentId && filePaths.contains(Column("filePath")))
                    .deleteAll(db)
            }
            loadFileClaims()
            return (true, "Released \(filePaths.count) file(s)")
        } catch {
            return (false, "Failed to release files: \(error)")
        }
    }

    /// Release all claims for an agent

    func releaseAllFiles(agentId: String) -> (success: Bool, message: String) {
        guard let projectId = currentProjectId else {
            return (false, "No project selected")
        }

        do {
            let count = try db.write { db -> Int in
                try DBFileClaim
                    .filter(Column("projectId") == projectId && Column("agentId") == agentId)
                    .deleteAll(db)
            }
            loadFileClaims()
            return (true, "Released \(count) file(s)")
        } catch {
            return (false, "Failed to release files: \(error)")
        }
    }

    func listClaimsFormatted() -> String {
        cleanupExpiredClaims()

        guard !fileClaims.isEmpty else {
            return "No files currently claimed"
        }

        var lines = ["## File Claims (TTL: \(Int(Self.claimTTLSeconds))s)\n"]
        let grouped = Dictionary(grouping: fileClaims) { $0.agentId }

        for (agentId, claims) in grouped.sorted(by: { $0.key < $1.key }) {
            let agentName = agents.first { $0.id == agentId }?.title ?? agentId
            lines.append("### \(agentName)")
            for claim in claims.sorted(by: { $0.filePath < $1.filePath }) {
                let remaining = Int(Self.claimTTLSeconds - Date().timeIntervalSince(claim.claimedAt))
                lines.append("- \(claim.filePath) (expires in \(remaining)s)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Check if files are available to claim. Returns status for each file.

    func checkClaims(_ filePaths: [String], agentId: String) -> [[String: Any]] {
        cleanupExpiredClaims()
        loadFileClaims()

        return filePaths.map { path -> [String: Any] in
            if let claim = fileClaims.first(where: { $0.filePath == path }) {
                if claim.agentId == agentId {
                    let remaining = Int(Self.claimTTLSeconds - Date().timeIntervalSince(claim.claimedAt))
                    return [
                        "file": path,
                        "status": "claimed_by_you",
                        "expires_in_seconds": max(0, remaining)
                    ]
                } else {
                    let agentName = agents.first { $0.id == claim.agentId }?.title ?? claim.agentId
                    let remaining = Int(Self.claimTTLSeconds - Date().timeIntervalSince(claim.claimedAt))
                    return [
                        "file": path,
                        "status": "blocked",
                        "claimed_by": agentName,
                        "expires_in_seconds": max(0, remaining)
                    ]
                }
            } else {
                return [
                    "file": path,
                    "status": "available"
                ]
            }
        }
    }

    func listTaskArtifactsFormatted(_ taskId: String) -> String {
        guard let artifacts = taskArtifacts[taskId], !artifacts.isEmpty else {
            return "No artifacts for task \(taskId)"
        }

        var lines = ["## Artifacts for task \(taskId)\n"]
        for artifact in artifacts {
            lines.append("- **\(artifact.label)** [id: \(artifact.id)] (type: \(artifact.type))\(formatArtifactDetails(artifact))")
        }
        return lines.joined(separator: "\n")
    }

    func listDeliverablesFormatted() -> String {
        if deliverables.isEmpty {
            return "No project deliverables"
        }

        var lines = ["## Project Deliverables\n"]
        for artifact in deliverables {
            lines.append("- **\(artifact.label)** [id: \(artifact.id)] (type: \(artifact.type))\(formatArtifactDetails(artifact))")
        }
        return lines.joined(separator: "\n")
    }

    private func formatArtifactDetails(_ artifact: DBArtifact) -> String {
        var details: [String] = []
        if let lang = artifact.language { details.append("language: \(lang)") }
        if let path = artifact.path { details.append("path: \(path)") }
        if let caption = artifact.caption, !caption.isEmpty { details.append("caption: \(caption)") }
        if details.isEmpty { return "" }
        return " (\(details.joined(separator: ", ")))"
    }
    
    func updateArtifactContent(_ artifactId: String, content: String) {
        do {
            try db.write { db in
                if var artifact = try DBArtifact.fetchOne(db, key: artifactId) {
                    artifact.file = content
                    try artifact.update(db)
                }
            }
            loadTaskData()
            loadAllTaskArtifacts()
            loadAllTaskCriteria()
        } catch {
            print("Failed to update artifact: \(error)")
        }
    }
    
    func getArtifact(_ artifactId: String) -> DBArtifact? {
        do {
            return try db.read { db in
                try DBArtifact.fetchOne(db, key: artifactId)
            }
        } catch {
            print("Failed to get artifact: \(error)")
            return nil
        }
    }

    func findArtifactByLabelAndType(taskId: String, label: String, type: String) -> DBArtifact? {
        do {
            return try db.read { db in
                try DBArtifact
                    .filter(Column("taskId") == taskId && Column("label") == label && Column("type") == type)
                    .fetchOne(db)
            }
        } catch {
            print("Failed to find artifact: \(error)")
            return nil
        }
    }

    func updateArtifactFull(_ artifactId: String, content: String, path: String?, language: String?, caption: String? = nil) {
        do {
            try db.write { db in
                if var artifact = try DBArtifact.fetchOne(db, key: artifactId) {
                    artifact.file = content
                    artifact.path = path
                    artifact.language = language
                    if let caption = caption {
                        artifact.caption = caption
                    }
                    try artifact.update(db)
                }
            }
            loadTaskData()
            loadAllTaskArtifacts()
            loadAllTaskCriteria()
        } catch {
            print("Failed to update artifact: \(error)")
        }
    }

    func getTaskListFormatted() -> String {
        var lines: [String] = ["## Current Tasks\n"]
        
        let active = tasks.filter { !$0.isProjectManager && !$0.isFinished }
        let finished = tasks.filter { !$0.isProjectManager && $0.isFinished }
        
        if active.isEmpty && finished.isEmpty {
            lines.append("No tasks yet.")
        } else {
            if !active.isEmpty {
                lines.append("### Active")
                for task in active {
                    lines.append("- **\(task.title)** [id: \(task.id)] - \(task.status)")
                }
            }
            if !finished.isEmpty {
                lines.append("\n### Completed")
                for task in finished {
                    lines.append("- ~~\(task.title)~~ [id: \(task.id)]")
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    func getTaskDetailsFormatted(_ taskId: String) -> String {
        guard let task = tasks.first(where: { $0.id == taskId }) else {
            return "Task not found: \(taskId)"
        }
        
        // Get criteria for this task
        let taskCriteria: [DBCriterion]
        do {
            taskCriteria = try db.read { db in
                try DBCriterion.filter(Column("taskId") == taskId).order(Column("order")).fetchAll(db)
            }
        } catch {
            taskCriteria = []
        }
        
        let autoCriteria = taskCriteria.filter { !$0.isHumanValidated }
        let humanCriteria = taskCriteria.filter { $0.isHumanValidated }
        
        var lines: [String] = [
            "## Task: \(task.title)",
            "**ID:** \(task.id)",
            "**Status:** \(task.status)",
            "**Description:** \(task.description.isEmpty ? "(none)" : task.description)",
            ""
        ]
        
        if !autoCriteria.isEmpty {
            lines.append("### Auto-Verified Criteria")
            for c in autoCriteria {
                let check = c.isValidated ? "x" : " "
                lines.append("- [\(check)] \(c.text) [id: \(c.id)]")
            }
        }
        
        if !humanCriteria.isEmpty {
            lines.append("\n### Human-Validated Criteria")
            for c in humanCriteria {
                let check = c.isValidated ? "x" : " "
                lines.append("- [\(check)] \(c.text) [id: \(c.id)] (human)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    func getTaskLogsFormatted(_ taskId: String) -> String {
        let taskLogs: [DBTaskLog]
        do {
            taskLogs = try db.read { db in
                try DBTaskLog.filter(Column("taskId") == taskId)
                    .order(Column("timestamp").desc)
                    .limit(20)
                    .fetchAll(db)
            }
        } catch {
            return "Error fetching logs"
        }
        
        if taskLogs.isEmpty {
            return "(no logs yet)"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        
        var lines: [String] = []
        for log in taskLogs.reversed() {
            let time = formatter.string(from: log.timestamp)
            let icon: String
            switch log.type {
            case "progress": icon = "⏳"
            case "info": icon = "ℹ️"
            case "success": icon = "✅"
            case "error": icon = "❌"
            case "query": icon = "❓"
            case "response": icon = "💬"
            default: icon = "•"
            }
            lines.append("[\(time)] \(icon) \(log.message)")
            if let details = log.details, !details.isEmpty {
                lines.append("    \(details.prefix(100))...")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    func updateTaskTitle(_ taskId: String, title: String) {
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    task.title = title
                    try task.update(db)
                }
            }
            loadTasks()
        } catch {
            print("Failed to update task title: \(error)")
        }
    }
    
    func updateTaskDescription(_ taskId: String, description: String) {
        do {
            try db.write { db in
                if var task = try DBTask.fetchOne(db, key: taskId) {
                    task.description = description
                    try task.update(db)
                }
            }
            loadTasks()
        } catch {
            print("Failed to update task description: \(error)")
        }
    }
    
    // MARK: - Agent Data (Messages, Artifacts)

    func loadTaskData() {

        // Load all agent messages into cache

        loadAllAgentMessages()

        // Refresh criteria and artifacts cache

        loadAllTaskCriteria()
        loadAllTaskArtifacts()

        // Load logs for current agent

        loadTaskCriteria()
    }

    // Load all messages for all agents into cache (for instant agent switching)

    func loadAllAgentMessages() {
        guard let projectId = currentProjectId else {
            agentMessages = [:]
            return
        }

        do {
            let allMessages = try db.read { db in
                try DBMessage
                    .joining(required: DBMessage.task.filter(Column("projectId") == projectId))
                    .order(Column("timestamp"))
                    .fetchAll(db)
            }

            // Group by agent (taskId)

            var cache: [String: [DBMessage]] = [:]
            for msg in allMessages {
                cache[msg.taskId, default: []].append(msg)
            }
            agentMessages = cache
        } catch {
            print("Failed to load agent messages: \(error)")
        }
    }

    // Legacy function for compatibility

    func loadChatMessages() {
        loadAllAgentMessages()
    }

    // Load logs for the currently selected task (criteria/artifacts use cache)

    func loadTaskCriteria() {
        guard let taskId = currentTaskId else {
            logs = []
            return
        }

        do {
            try db.read { db in
                logs = try DBTaskLog
                    .filter(Column("taskId") == taskId)
                    .order(Column("timestamp"))
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load task logs: \(error)")
        }
    }

    // MARK: - Auto-Start Sessions

    func autoStartAllSessions() {
        let manager = ClaudeCodeManager.shared

        for project in projects {
            let projectPath = project.localPath.isEmpty ? nil : project.localPath

            // Start Agent session

            let agentSessionId = ClaudeCodeManager.agentSessionId(projectId: project.id)
            if manager.sessions[agentSessionId] == nil {
                let session = manager.getOrCreateSession(
                    id: agentSessionId,
                    workingDirectory: projectPath,
                    persona: .agent,
                    projectId: project.id
                )
                session.start()
                print("✓ Auto-started Agent session for project: \(project.name)")
            }
        }
    }

    // MARK: - Messages

    func addMessage(role: String, text: String, persona: String? = nil, toAgentId: String? = nil) {
        let messagePersona = persona ?? "agent"

        // Store message to specified agent or current agent

        let agentId = toAgentId ?? currentAgentId
        guard let agentId = agentId else { return }

        let message = DBMessage(taskId: agentId, role: role, text: text, persona: messagePersona)
        do {
            try db.write { db in
                try message.insert(db)
            }

            // Append to cache

            if agentMessages[agentId] == nil {
                agentMessages[agentId] = []
            }
            agentMessages[agentId]?.append(message)
        } catch {
            print("Failed to add message: \(error)")
        }
    }
    
    // MARK: - Criteria
    
    func addCriterion(text: String, isHumanValidated: Bool = false, fromUI: Bool = false) {
        guard let taskId = currentTaskId else { return }
        _ = addCriterion(taskId: taskId, text: text, isHumanValidated: isHumanValidated, fromUI: fromUI)
    }

    /// Add criterion to specific task (for MCP/CLI)
    @discardableResult
    func addCriterion(taskId: String, text: String, isHumanValidated: Bool = false, fromUI: Bool = false) -> String {
        let criterion: DBCriterion
        do {

            // Get existing count for ordering

            let existingCount = try db.read { db in
                try DBCriterion.filter(Column("taskId") == taskId).fetchCount(db)
            }
            criterion = DBCriterion(taskId: taskId, text: text, isHumanValidated: isHumanValidated, order: existingCount)
            try db.write { db in
                try criterion.insert(db)
            }
            loadTaskData()
            return criterion.id
        } catch {
            print("Failed to add criterion: \(error)")
            return ""
        }
    }
    
    func updateCriterion(_ criterionId: String, text: String, fromUI: Bool = false) {
        do {
            try db.write { db in
                if var criterion = try DBCriterion.fetchOne(db, key: criterionId) {
                    criterion.text = text
                    try criterion.update(db)
                }
            }
            loadTaskData()
        } catch {
            print("Failed to update criterion: \(error)")
        }
    }
    
    func toggleCriterion(_ criterionId: String, fromUI: Bool = false) {
        do {
            try db.write { db in
                if var criterion = try DBCriterion.fetchOne(db, key: criterionId) {
                    criterion.isValidated.toggle()
                    try criterion.update(db)
                }
            }
            loadTaskData()
        } catch {
            print("Failed to toggle criterion: \(error)")
        }
    }
    
    func verifyCriterion(_ criterionId: String, fromUI: Bool = false) {
        var criterionText = ""
        do {
            try db.write { db in
                if var criterion = try DBCriterion.fetchOne(db, key: criterionId) {
                    criterion.isValidated = true
                    criterionText = criterion.text
                    try criterion.update(db)
                }
            }
            loadTaskData()

            // Notify Claude if change came from UI

            if fromUI && !criterionText.isEmpty {
                notifyCriterionChange(criterionId, change: "Criterion ✅ verified: \"\(criterionText)\"")
            }
        } catch {
            print("Failed to verify criterion: \(error)")
        }
    }

    func setCriterionStatus(_ criterionId: String, verified: Bool, fromUI: Bool = false) {
        var criterionText = ""
        do {
            try db.write { db in
                if var criterion = try DBCriterion.fetchOne(db, key: criterionId) {
                    criterion.isValidated = verified
                    criterionText = criterion.text
                    try criterion.update(db)
                }
            }
            loadTaskData()

            // Notify Claude if change came from UI

            if fromUI && !criterionText.isEmpty {
                let status = verified ? "✅ verified" : "⬜ unverified"
                notifyCriterionChange(criterionId, change: "Criterion \(status): \"\(criterionText)\"")
            }
        } catch {
            print("Failed to set criterion status: \(error)")
        }
    }

    func listCriteriaFormatted(_ taskId: String) -> String {
        do {
            let taskCriteria = try db.read { db in
                try DBCriterion.filter(Column("taskId") == taskId).order(Column("order")).fetchAll(db)
            }
            
            if taskCriteria.isEmpty {
                return "No criteria defined for this task."
            }
            
            var result = ""
            let autoCriteria = taskCriteria.filter { !$0.isHumanValidated }
            let humanCriteria = taskCriteria.filter { $0.isHumanValidated }
            
            if !autoCriteria.isEmpty {
                result += "**Auto-Verified Criteria:**\n"
                for c in autoCriteria {
                    let status = c.isValidated ? "✅" : "⬜"
                    result += "\(status) \(c.text) (id: \(c.id))\n"
                }
            }
            
            if !humanCriteria.isEmpty {
                if !result.isEmpty { result += "\n" }
                result += "**Human-Validated Criteria** (only humans can verify these):\n"
                for c in humanCriteria {
                    let status = c.isValidated ? "✅" : "⏳"
                    result += "\(status) \(c.text) (id: \(c.id))\n"
                }
            }
            
            return result
        } catch {
            return "Error loading criteria: \(error)"
        }
    }
    
    func deleteCriterion(_ criterionId: String, fromUI: Bool = false) {
        do {
            try db.write { db in
                try DBCriterion.deleteOne(db, key: criterionId)
            }
            loadTaskData()
        } catch {
            print("Failed to delete criterion: \(error)")
        }
    }
    
    // MARK: - Logs
    
    func addLog(type: String, message: String, details: String? = nil) {
        guard let taskId = currentTaskId else { return }
        
        let log = DBTaskLog(taskId: taskId, type: type, message: message, details: details)
        do {
            try db.write { db in
                try log.insert(db)
            }
            loadTaskData()
        } catch {
            print("Failed to add log: \(error)")
        }
    }
    
    // MARK: - App State
    
    private func loadAppState() {
        do {
            try db.read { db in
                if let state = try DBAppState.fetchOne(db, key: "currentProjectId") {
                    currentProjectId = state.value
                }
            }
            if currentProjectId != nil {
                loadTasks()
                if let manager = projectManager {
                    selectTask(manager.id)
                }
            }
        } catch {
            print("Failed to load app state: \(error)")
        }
    }
    
    private func saveAppState() {
        do {
            try db.write { db in
                if let projectId = currentProjectId {
                    let state = DBAppState(key: "currentProjectId", value: projectId)
                    try state.save(db)
                }
            }
        } catch {
            print("Failed to save app state: \(error)")
        }
    }
    
    // MARK: - Tool Execution (Engineer)
    
    func executeTool(_ toolName: String, args: [String: Any]) -> String {
        switch toolName {
        case "read_file":
            let path = args["path"] as? String ?? ""
            return readProjectFile(path: path)
            
        case "write_file":
            let path = args["path"] as? String ?? ""
            let content = args["content"] as? String ?? ""
            return writeProjectFile(path: path, content: content)
            
        case "list_files":
            let path = args["path"] as? String ?? ""
            return listProjectFiles(path: path)
            
        case "exec_command":
            let command = args["command"] as? String ?? ""
            return executeCommand(command: command)

        // MCP Tools - real-time communication
        case "send_message":
            let message = args["message"] as? String ?? ""
            return callMCP(tool: "send_message", params: ["message": message])

        case "list_criteria":
            return callMCP(tool: "list_criteria", params: [:])

        case "verify_criterion":
            let criterionId = args["criterion_id"] as? String ?? ""
            return callMCP(tool: "verify_criterion", params: ["criterion_id": criterionId])

        case "add_deliverable":
            let type = args["type"] as? String ?? ""
            let label = args["label"] as? String ?? ""
            let content = args["content"] as? String ?? ""
            return callMCP(tool: "add_deliverable", params: ["type": type, "label": label, "content": content])

        case "list_deliverables":
            return callMCP(tool: "list_deliverables", params: [:])

        default:
            return "Unknown tool: \(toolName)"
        }
    }

    // MARK: - MCP Server Calls

    private func callMCP(tool: String, params: [String: String]) -> String {
        guard let url = URL(string: "http://localhost:9999/execute") else {
            return "Error: Invalid MCP server URL"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "tool": tool,
            "params": params
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            // Use semaphore to wait for async response
            let semaphore = DispatchSemaphore(value: 0)
            var result = "Error: No response from MCP"

            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { semaphore.signal() }

                if let error = error {
                    result = "Error: \(error.localizedDescription)"
                    return
                }

                if let data = data, let response = String(data: data, encoding: .utf8) {
                    result = response
                }
            }.resume()

            _ = semaphore.wait(timeout: .now() + 30)
            return result
        } catch {
            return "Error calling MCP: \(error.localizedDescription)"
        }
    }
    
    // MARK: - File Operations (Engineer)
    
    private func getProjectPath() -> URL? {
        guard let projectId = currentProjectId,
              let project = projects.first(where: { $0.id == projectId }),
              !project.localPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: project.localPath)
    }
    
    func readProjectFile(path: String) -> String {
        guard let projectPath = getProjectPath() else {
            return "Error: No project path configured"
        }
        
        let fullPath = projectPath.appendingPathComponent(path)
        
        // Security: ensure path is within project directory
        guard fullPath.path.hasPrefix(projectPath.path) else {
            return "Error: Path must be within project directory"
        }
        
        do {
            let content = try String(contentsOf: fullPath, encoding: .utf8)
            return content
        } catch {
            return "Error reading file: \(error.localizedDescription)"
        }
    }
    
    func writeProjectFile(path: String, content: String) -> String {
        guard let projectPath = getProjectPath() else {
            return "Error: No project path configured"
        }
        
        let fullPath = projectPath.appendingPathComponent(path)
        
        // Security: ensure path is within project directory
        guard fullPath.path.hasPrefix(projectPath.path) else {
            return "Error: Path must be within project directory"
        }
        
        do {
            // Create parent directories if needed
            let parentDir = fullPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            
            try content.write(to: fullPath, atomically: true, encoding: .utf8)
            return "Successfully wrote \(content.count) bytes to \(path)"
        } catch {
            return "Error writing file: \(error.localizedDescription)"
        }
    }
    
    func listProjectFiles(path: String) -> String {
        guard let projectPath = getProjectPath() else {
            return "Error: No project path configured"
        }
        
        let targetPath = path.isEmpty ? projectPath : projectPath.appendingPathComponent(path)
        
        // Security: ensure path is within project directory
        guard targetPath.path.hasPrefix(projectPath.path) else {
            return "Error: Path must be within project directory"
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: targetPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            var result: [String] = []
            for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let name = url.lastPathComponent + (isDir ? "/" : "")
                result.append(name)
            }
            
            return result.isEmpty ? "(empty directory)" : result.joined(separator: "\n")
        } catch {
            return "Error listing directory: \(error.localizedDescription)"
        }
    }
    
    func executeCommand(command: String) -> String {
        guard let projectPath = getProjectPath() else {
            return "Error: No project path configured"
        }
        
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = projectPath
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            var result = ""
            if !output.isEmpty {
                result += output
            }
            if !errorOutput.isEmpty {
                result += (result.isEmpty ? "" : "\n") + "stderr: " + errorOutput
            }
            if process.terminationStatus != 0 {
                result += (result.isEmpty ? "" : "\n") + "Exit code: \(process.terminationStatus)"
            }
            
            return result.isEmpty ? "(no output)" : result
        } catch {
            return "Error executing command: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Migration from JSON (call once on first run)
    
    func migrateFromJSON() {
        let basePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".daisy-projects")
        
        let manifestPath = basePath.appendingPathComponent("projects.json")
        guard FileManager.default.fileExists(atPath: manifestPath.path) else { return }
        
        // Check if already migrated
        if !projects.isEmpty { return }
        
        print("Migrating from JSON...")
        
        // Read old manifest
        guard let data = try? Data(contentsOf: manifestPath),
              let json = try? JSONDecoder().decode(OldProjectsManifest.self, from: data) else {
            return
        }
        
        for oldProject in json.projects {
            let project = createProject(name: oldProject.name)
            
            // Migrate tasks
            let tasksPath = basePath.appendingPathComponent(oldProject.id).appendingPathComponent("tasks/tasks.json")
            if let tasksData = try? Data(contentsOf: tasksPath) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let tasksManifest = try? decoder.decode(OldTasksManifest.self, from: tasksData) {
                    for oldTask in tasksManifest.tasks {
                        // Create task in DB
                        let task = DBTask(
                            id: oldTask.id,
                            projectId: project.id,
                            title: oldTask.title,
                            description: oldTask.description
                        )
                        do {
                            try db.write { db in
                                try task.insert(db)
                                
                                // Migrate criteria
                                for (i, c) in oldTask.successCriteria.enumerated() {
                                    let criterion = DBCriterion(
                                        id: c.id,
                                        taskId: task.id,
                                        text: c.text,
                                        isHumanValidated: false,
                                        order: i
                                    )
                                    try criterion.insert(db)
                                }
                                
                                for (i, c) in oldTask.humanValidatedCriteria.enumerated() {
                                    let criterion = DBCriterion(
                                        id: c.id,
                                        taskId: task.id,
                                        text: c.text,
                                        isHumanValidated: true,
                                        order: oldTask.successCriteria.count + i
                                    )
                                    try criterion.insert(db)
                                }
                            }
                        } catch {
                            print("Failed to migrate task: \(error)")
                        }
                    }
                }
            }
            
            // Migrate messages
            let messagesPath = basePath.appendingPathComponent(oldProject.id).appendingPathComponent("messages.json")
            if let messagesData = try? Data(contentsOf: messagesPath),
               let oldMessages = try? JSONDecoder().decode([OldMessage].self, from: messagesData) {
                // Find the project manager task
                if let manager = try? db.read({ db in
                    try DBTask
                        .filter(Column("projectId") == project.id)
                        .filter(Column("isProjectManager") == true)
                        .fetchOne(db)
                }) {
                    for oldMsg in oldMessages {
                        let message = DBMessage(
                            taskId: manager.id,
                            role: oldMsg.role.rawValue,
                            text: oldMsg.text
                        )
                        try? db.write { db in
                            try message.insert(db)
                        }
                    }
                }
            }
        }
        
        loadProjects()
        if let first = projects.first {
            selectProject(first.id)
        }
        
        print("Migration complete!")
    }
}
