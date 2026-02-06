import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// -------------------------------------------------------------------------------------
// --------------------------------- FirebaseManager -----------------------------------
// -------------------------------------------------------------------------------------

@MainActor
class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    @Published var isSignedIn: Bool = false
    @Published var userId: String?
    @Published var userEmail: String?

    let db: Firestore

    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        db = Firestore.firestore()
        setupAuthListener()
    }

    // -------------------------------------------------------------------------------------
    // ------------------------------------ Auth -------------------------------------------
    // -------------------------------------------------------------------------------------

    private func setupAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isSignedIn = user != nil
                self?.userId = user?.uid
                self?.userEmail = user?.email
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        await MainActor.run {
            isSignedIn = true
            userId = result.user.uid
            userEmail = result.user.email
        }
    }

    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        await MainActor.run {
            isSignedIn = true
            userId = result.user.uid
            userEmail = result.user.email
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
        isSignedIn = false
        userId = nil
        userEmail = nil
    }

    // -------------------------------------------------------------------------------------
    // --------------------------------- Collection Refs -----------------------------------
    // -------------------------------------------------------------------------------------

    // All data lives under: users/{userId}/...

    func userDoc() -> DocumentReference? {
        guard let uid = userId else { return nil }
        return db.collection("users").document(uid)
    }

    func projectsCollection() -> CollectionReference? {
        userDoc()?.collection("projects")
    }

    func agentsCollection(projectId: String) -> CollectionReference? {
        userDoc()?.collection("projects").document(projectId).collection("agents")
    }

    func messagesCollection(agentId: String) -> CollectionReference? {
        userDoc()?.collection("messages_\(agentId)")
    }

    func artifactsCollection(agentId: String) -> CollectionReference? {
        userDoc()?.collection("artifacts_\(agentId)")
    }

    func fileClaimsCollection(projectId: String) -> CollectionReference? {
        userDoc()?.collection("projects").document(projectId).collection("fileClaims")
    }

    // -------------------------------------------------------------------------------------
    // ----------------------------------- Projects ----------------------------------------
    // -------------------------------------------------------------------------------------

    func createProject(_ project: [String: Any]) async throws {
        guard let collection = projectsCollection() else { return }
        guard let id = project["id"] as? String else { return }
        try await collection.document(id).setData(project)
    }

    func updateProject(_ projectId: String, data: [String: Any]) async throws {
        guard let collection = projectsCollection() else { return }
        try await collection.document(projectId).updateData(data)
    }

    func deleteProject(_ projectId: String) async throws {
        guard let collection = projectsCollection() else { return }
        try await collection.document(projectId).delete()
    }

    // -------------------------------------------------------------------------------------
    // ------------------------------------ Agents -----------------------------------------
    // -------------------------------------------------------------------------------------

    func createAgent(_ agent: [String: Any], projectId: String) async throws {
        guard let collection = agentsCollection(projectId: projectId) else { return }
        guard let id = agent["id"] as? String else { return }
        try await collection.document(id).setData(agent)
    }

    func updateAgent(_ agentId: String, projectId: String, data: [String: Any]) async throws {
        guard let collection = agentsCollection(projectId: projectId) else { return }
        try await collection.document(agentId).updateData(data)
    }

    func deleteAgent(_ agentId: String, projectId: String) async throws {
        guard let collection = agentsCollection(projectId: projectId) else { return }
        try await collection.document(agentId).delete()
    }

    // -------------------------------------------------------------------------------------
    // ----------------------------------- Messages ----------------------------------------
    // -------------------------------------------------------------------------------------

    func addMessage(_ message: [String: Any], agentId: String) async throws {
        guard let collection = messagesCollection(agentId: agentId) else { return }
        guard let id = message["id"] as? String else { return }
        try await collection.document(id).setData(message)
    }

    func deleteMessages(agentId: String) async throws {
        guard let collection = messagesCollection(agentId: agentId) else { return }
        let snapshot = try await collection.getDocuments()
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }

    // -------------------------------------------------------------------------------------
    // ----------------------------------- Artifacts ---------------------------------------
    // -------------------------------------------------------------------------------------

    func addArtifact(_ artifact: [String: Any], agentId: String) async throws {
        guard let collection = artifactsCollection(agentId: agentId) else { return }
        guard let id = artifact["id"] as? String else { return }
        try await collection.document(id).setData(artifact)
    }

    func updateArtifact(_ artifactId: String, agentId: String, data: [String: Any]) async throws {
        guard let collection = artifactsCollection(agentId: agentId) else { return }
        try await collection.document(artifactId).updateData(data)
    }

    func deleteArtifact(_ artifactId: String, agentId: String) async throws {
        guard let collection = artifactsCollection(agentId: agentId) else { return }
        try await collection.document(artifactId).delete()
    }

    func deleteAllArtifacts(agentId: String) async throws {
        guard let collection = artifactsCollection(agentId: agentId) else { return }
        let snapshot = try await collection.getDocuments()
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }

    // -------------------------------------------------------------------------------------
    // --------------------------------- File Claims ---------------------------------------
    // -------------------------------------------------------------------------------------

    func claimFile(_ claim: [String: Any], projectId: String) async throws {
        guard let collection = fileClaimsCollection(projectId: projectId) else { return }
        guard let id = claim["id"] as? String else { return }
        try await collection.document(id).setData(claim)
    }

    func releaseClaim(_ claimId: String, projectId: String) async throws {
        guard let collection = fileClaimsCollection(projectId: projectId) else { return }
        try await collection.document(claimId).delete()
    }
}
