import Foundation
import GRDB
import FirebaseFirestore

// -------------------------------------------------------------------------------------
// ----------------------------------- DataStore ---------------------------------------
// -------------------------------------------------------------------------------------

@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var projects: [DBProject] = []
    @Published var currentProjectId: String?
    @Published var currentAgentId: String?

    // All agents for current project

    @Published var agents: [DBAgent] = []

    // Per-agent message cache for instant switching

    @Published var agentMessages: [String: [DBMessage]] = [:]

    // Per-agent artifact cache

    @Published var agentArtifacts: [String: [DBArtifact]] = [:]
    @Published var selectedArtifactId: String?

    // File claims for parallel agent coordination

    @Published var fileClaims: [DBFileClaim] = []

    // Project settings sheet

    @Published var showProjectSettings: Bool = false

    private let db = DatabaseManager.shared
    private let firebase = FirebaseManager.shared

    // Firestore listener for mobile-originated messages

    private var mobileMessageListeners: [String: ListenerRegistration] = [:]

    private init() {
        loadProjects()
        loadAppState()
    }

    // -------------------------------------------------------------------------------------
    // ------------------------------- Firestore Sync Helpers ------------------------------
    // -------------------------------------------------------------------------------------

    private func syncProjectToFirestore(_ project: DBProject) {
        Task {
            let data: [String: Any] = [
                "id": project.id,
                "name": project.name,
                "description": project.description,
                "localPath": project.localPath,
                "order": project.order,
                "createdAt": Timestamp(date: project.createdAt)
            ]
            try? await firebase.createProject(data)
        }
    }

    private func syncAgentToFirestore(_ agent: DBAgent) {
        guard let projectId = currentProjectId else { return }
        Task {
            let data: [String: Any] = [
                "id": agent.id,
                "projectId": agent.projectId,
                "title": agent.title,
                "description": agent.description,
                "isDefault": agent.isDefault,
                "isFinished": agent.isFinished,
                "status": agent.status,
                "createdAt": Timestamp(date: agent.createdAt)
            ]
            try? await firebase.createAgent(data, projectId: projectId)
        }
    }

    private func syncMessageToFirestore(_ message: DBMessage) {
        Task {
            let data: [String: Any] = [
                "id": message.id,
                "agentId": message.taskId,
                "role": message.role,
                "text": message.text,
                "timestamp": Timestamp(date: message.timestamp),
                "persona": message.persona,
                "source": "desktop"
            ]
            try? await firebase.addMessage(data, agentId: message.taskId)
        }
    }

    private func syncArtifactToFirestore(_ artifact: DBArtifact) {
        Task {
            var data: [String: Any] = [
                "id": artifact.id,
                "agentId": artifact.taskId,
                "type": artifact.type,
                "label": artifact.label,
                "content": artifact.file,
                "order": artifact.order
            ]
            if let path = artifact.path { data["path"] = path }
            if let lang = artifact.language { data["language"] = lang }
            if let caption = artifact.caption { data["caption"] = caption }
            try? await firebase.addArtifact(data, agentId: artifact.taskId)
        }
    }

    // -------------------------------------------------------------------------------------
    // ----------------------------- Mobile Message Listener -------------------------------
    // -------------------------------------------------------------------------------------

    func startMobileMessageListeners() {
        for agent in agents {
            listenForMobileMessages(agentId: agent.id)
        }
    }

    func stopMobileMessageListeners() {
        for (_, listener) in mobileMessageListeners {
            listener.remove()
        }
        mobileMessageListeners.removeAll()
    }

    private func listenForMobileMessages(agentId: String) {
        mobileMessageListeners[agentId]?.remove()

        guard let collection = firebase.messagesCollection(agentId: agentId) else { return }

        mobileMessageListeners[agentId] = collection
            .whereField("source", isEqualTo: "mobile")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                guard let changes = snapshot?.documentChanges else { return }

                for change in changes where change.type == .added {
                    let d = change.document.data()
                    let text = d["text"] as? String ?? ""
                    let messageId = d["id"] as? String ?? change.document.documentID

                    // Check if we already have this message locally

                    let existing = self.agentMessages[agentId]?.contains { $0.id == messageId } ?? false
                    if existing { continue }

                    Task { @MainActor in

                        // Add to local DB

                        self.addMessage(role: "user", text: text, persona: "agent", toAgentId: agentId)

                        // Send to the Claude Code tmux session

                        guard let projectId = self.currentProjectId,
                              let agent = self.agents.first(where: { $0.id == agentId }) else { return }

                        let sessionId: String
                        if agent.isDefault {
                            sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)
                        } else {
                            sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agentId)
                        }

                        if let session = ClaudeCodeManager.shared.sessions[sessionId], session.isRunning {
                            session.sendLine(text)
                            MCPServer.shared.setTyping(sessionId: sessionId, typing: true)
                        }
                    }
                }
            }
    }

    // Messages for the current agent's conversation (from cache)

    var messages: [DBMessage] {
        guard let agentId = currentAgentId else { return [] }
        return agentMessages[agentId] ?? []
    }

    // Artifacts for the current agent

    var artifacts: [DBArtifact] {
        guard let agentId = currentAgentId else { return [] }
        return agentArtifacts[agentId] ?? []
    }

    // Sorted agents: default first, then by creation date

    var sortedAgents: [DBAgent] {
        agents.sorted { a, b in
            if a.isDefault { return true }
            if b.isDefault { return false }
            return a.createdAt < b.createdAt
        }
    }

    // Default agent for current project

    var defaultAgent: DBAgent? {
        agents.first { $0.isDefault }
    }

    // -------------------------------------------------------------------------------------
    // ----------------------------------- Projects ----------------------------------------
    // -------------------------------------------------------------------------------------

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
            var defaultAgent = DBTask(projectId: project.id, title: "General", isProjectManager: true)
            defaultAgent.status = "running"

            try db.write { db in
                try project.insert(db)
                try defaultAgent.insert(db)
            }

            loadProjects()
            selectProject(project.id)

            // Sync to Firestore

            syncProjectToFirestore(project)
            syncAgentToFirestore(defaultAgent)

            // Auto-start session after UI settles

            let projectCopy = project
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startSessionsForProject(projectCopy)
            }
        } catch {
            print("Failed to create project: \(error)")
        }
        return project
    }

    func deleteProject(_ projectId: String) {
        do {
            try db.write { db in
                try DBProject.deleteOne(db, key: projectId)
            }
            loadProjects()
            if currentProjectId == projectId {
                currentProjectId = projects.first?.id
                loadAgents()
            }

            Task { try? await firebase.deleteProject(projectId) }
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

            Task { try? await firebase.updateProject(projectId, data: ["name": name]) }
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
        loadAgents()
        loadFileClaims()

        // Auto-select default agent

        if let agent = sortedAgents.first {
            selectAgent(agent.id)
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

    // -------------------------------------------------------------------------------------
    // ------------------------------------ Agents -----------------------------------------
    // -------------------------------------------------------------------------------------

    func loadAgents() {
        guard let projectId = currentProjectId else {
            agents = []
            agentMessages = [:]
            return
        }

        do {
            agents = try db.read { db in
                try DBTask
                    .filter(Column("projectId") == projectId)
                    .fetchAll(db)
            }
            loadAllAgentArtifacts()
            loadAllAgentMessages()

            // Listen for messages from mobile

            startMobileMessageListeners()
        } catch {
            print("Failed to load agents: \(error)")
        }
    }

    func selectAgent(_ agentId: String) {
        currentAgentId = agentId
    }

    @discardableResult
    func addAgent() -> DBAgent {
        guard let projectId = currentProjectId else {
            fatalError("No project selected")
        }

        // Pick a random name that's not already used in this project

        let usedNames = Set(agents.filter { !$0.isDefault }.map { $0.title })
        let availableNames = agentNames.filter { !usedNames.contains($0) }
        let agentName: String

        if let randomName = availableNames.randomElement() {
            agentName = randomName
        } else {
            agentName = "Agent \(agents.count + 1)"
        }

        let agent = DBTask(projectId: projectId, title: agentName)
        do {
            try db.write { db in
                try agent.insert(db)
            }
            loadAgents()
            selectAgent(agent.id)
            syncAgentToFirestore(agent)

            // Start a Claude session for this agent

            startAgentSession(agentId: agent.id)
        } catch {
            print("Failed to add agent: \(error)")
        }
        return agent
    }

    func renameAgent(_ agentId: String, name: String) {
        do {
            try db.write { db in
                if var agent = try DBTask.fetchOne(db, key: agentId) {
                    agent.title = name
                    try agent.update(db)
                }
            }
            loadAgents()
        } catch {
            print("Failed to rename agent: \(error)")
        }
    }

    func deleteAgent(_ agentId: String) {
        guard let agent = agents.first(where: { $0.id == agentId }),
              !agent.isDefault else {
            print("Cannot delete default agent")
            return
        }

        let projectId = agent.projectId

        // Stop the agent's session

        stopAgentSession(agentId: agentId)

        do {
            try db.write { db in
                try DBTask.deleteOne(db, key: agentId)
            }
            loadAgents()
            if currentAgentId == agentId {
                currentAgentId = sortedAgents.first?.id
            }

            Task { try? await firebase.deleteAgent(agentId, projectId: projectId) }
        } catch {
            print("Failed to delete agent: \(error)")
        }
    }

    func moveAgentUp(_ agentId: String) {
        let nonDefault = sortedAgents.filter { !$0.isDefault }
        guard let index = nonDefault.firstIndex(where: { $0.id == agentId }), index > 0 else { return }
        swapAgentOrder(nonDefault[index], nonDefault[index - 1])
    }

    func moveAgentDown(_ agentId: String) {
        let nonDefault = sortedAgents.filter { !$0.isDefault }
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
            loadAgents()
        } catch {
            print("Failed to swap agent order: \(error)")
        }
    }

    // -------------------------------------------------------------------------------------
    // ---------------------------------- Sessions -----------------------------------------
    // -------------------------------------------------------------------------------------

    func startSessionsForProject(_ project: DBProject) {
        let manager = ClaudeCodeManager.shared
        let projectPath = project.localPath.isEmpty ? nil : project.localPath

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

    func startAgentSession(agentId: String) {
        guard let projectId = currentProjectId,
              let project = projects.first(where: { $0.id == projectId }),
              let agent = agents.first(where: { $0.id == agentId }) else { return }

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

    func stopAgentSession(agentId: String) {
        guard let projectId = currentProjectId else { return }
        let manager = ClaudeCodeManager.shared
        let sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agentId)
        manager.removeSession(id: sessionId)
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

        addMessage(role: "system", text: "Context cleared — session restarted", toAgentId: currentAgentId)
    }

    func clearMessageHistory() {
        guard let agentId = currentAgentId else { return }

        do {
            try db.write { db in
                try db.execute(sql: "DELETE FROM message WHERE taskId = ?", arguments: [agentId])
            }

            agentMessages[agentId] = []
        } catch {
            print("Failed to clear message history: \(error)")
        }
    }

    func clearAllMessageHistory() {
        guard let projectId = currentProjectId else { return }

        let projectAgents = agents.filter { $0.projectId == projectId }

        do {
            try db.write { db in
                for agent in projectAgents {
                    try db.execute(sql: "DELETE FROM message WHERE taskId = ?", arguments: [agent.id])
                }
            }
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

            MCPServer.shared.setTyping(sessionId: sessionId, typing: false)

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

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    session.sendLine(message)
                }
            }
        }
    }

    func autoStartAllSessions() {
        let manager = ClaudeCodeManager.shared

        for project in projects {
            let projectPath = project.localPath.isEmpty ? nil : project.localPath

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

    // -------------------------------------------------------------------------------------
    // ---------------------------------- Messages -----------------------------------------
    // -------------------------------------------------------------------------------------

    func addMessage(role: String, text: String, persona: String? = nil, toAgentId: String? = nil) {
        let messagePersona = persona ?? "agent"

        let agentId = toAgentId ?? currentAgentId
        guard let agentId = agentId else { return }

        let message = DBMessage(taskId: agentId, role: role, text: text, persona: messagePersona)
        do {
            try db.write { db in
                try message.insert(db)
            }

            if agentMessages[agentId] == nil {
                agentMessages[agentId] = []
            }
            agentMessages[agentId]?.append(message)
            syncMessageToFirestore(message)
        } catch {
            print("Failed to add message: \(error)")
        }
    }

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

            var cache: [String: [DBMessage]] = [:]
            for msg in allMessages {
                cache[msg.taskId, default: []].append(msg)
            }
            agentMessages = cache
        } catch {
            print("Failed to load agent messages: \(error)")
        }
    }

    // -------------------------------------------------------------------------------------
    // ---------------------------------- Artifacts ----------------------------------------
    // -------------------------------------------------------------------------------------

    func loadAllAgentArtifacts() {
        guard currentProjectId != nil else {
            agentArtifacts = [:]
            return
        }

        // Only load artifacts for agents in the current project

        let projectAgentIds = agents.map { $0.id }

        do {
            let allArtifacts = try db.read { db in
                try DBArtifact
                    .filter(projectAgentIds.contains(Column("taskId")))
                    .order(Column("order"))
                    .fetchAll(db)
            }
            var grouped: [String: [DBArtifact]] = [:]
            for artifact in allArtifacts {
                grouped[artifact.taskId, default: []].append(artifact)
            }
            agentArtifacts = grouped
        } catch {
            print("Failed to load agent artifacts: \(error)")
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
            loadAllAgentArtifacts()
            syncArtifactToFirestore(artifact)
            return artifact.id
        } catch {
            print("Failed to add artifact: \(error)")
            return nil
        }
    }

    func updateArtifact(_ artifactId: String, content: String) {
        updateArtifactContent(artifactId, content: content)
    }

    func updateArtifactContent(_ artifactId: String, content: String) {
        do {
            try db.write { db in
                if var artifact = try DBArtifact.fetchOne(db, key: artifactId) {
                    artifact.file = content
                    try artifact.update(db)
                }
            }
            loadAllAgentArtifacts()
        } catch {
            print("Failed to update artifact: \(error)")
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
            loadAllAgentArtifacts()
        } catch {
            print("Failed to update artifact: \(error)")
        }
    }

    func deleteArtifact(_ artifactId: String) {
        do {
            try db.write { db in
                try DBArtifact.deleteOne(db, key: artifactId)
            }
            if selectedArtifactId == artifactId {
                selectedArtifactId = nil
            }
            loadAllAgentArtifacts()
        } catch {
            print("Failed to delete artifact: \(error)")
        }
    }

    func deleteAllAgentArtifacts(_ agentId: String) {
        do {
            try db.write { db in
                try DBArtifact.filter(Column("taskId") == agentId).deleteAll(db)
            }
            if currentAgentId == agentId {
                selectedArtifactId = nil
            }
            loadAllAgentArtifacts()
        } catch {
            print("Failed to delete all agent artifacts: \(error)")
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

    func selectArtifact(_ artifactId: String?) {
        selectedArtifactId = artifactId
    }

    // ------------------------------------- Artifact Reordering ---------------------------

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

        let orderA = artifactA.order
        let orderB = artifactB.order

        do {
            try db.write { db in
                try db.execute(sql: "UPDATE artifact SET \"order\" = ? WHERE id = ?", arguments: [orderB, artifactA.id])
                try db.execute(sql: "UPDATE artifact SET \"order\" = ? WHERE id = ?", arguments: [orderA, artifactB.id])
            }
            loadAllAgentArtifacts()
        } catch {
            print("Failed to swap artifact order: \(error)")
        }
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
            loadAllAgentArtifacts()
        } catch {
            print("Failed to add CSV artifact: \(error)")
        }
    }

    // -------------------------------------------------------------------------------------
    // --------------------------------- File Claims ---------------------------------------
    // -------------------------------------------------------------------------------------

    static let claimTTLSeconds: TimeInterval = 120

    func loadFileClaims() {
        guard let projectId = currentProjectId else {
            fileClaims = []
            return
        }

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

    func claimFiles(_ filePaths: [String], agentId: String) -> (success: Bool, message: String) {
        guard let projectId = currentProjectId else {
            return (false, "No project selected")
        }

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

    // -------------------------------------------------------------------------------------
    // ---------------------------------- App State ----------------------------------------
    // -------------------------------------------------------------------------------------

    private func loadAppState() {
        do {
            try db.read { db in
                if let state = try DBAppState.fetchOne(db, key: "currentProjectId") {
                    currentProjectId = state.value
                }
            }
            if currentProjectId != nil {
                loadAgents()
                if let agent = sortedAgents.first {
                    selectAgent(agent.id)
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
}
