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

    // -------------------------------------------------------------------------------------
    // ----------------------------------- Messages ----------------------------------------
    // -------------------------------------------------------------------------------------

    func addMessage(_ message: [String: Any], agentId: String) async throws {
        guard let collection = messagesCollection(agentId: agentId) else { return }
        guard let id = message["id"] as? String else { return }
        try await collection.document(id).setData(message)
    }
}
