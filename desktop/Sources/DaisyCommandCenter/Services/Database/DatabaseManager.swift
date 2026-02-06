import Foundation
import GRDB

// MARK: - Database Manager

class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue!

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".daisy-command-center/daisy.db")

        // Ensure directory exists

        let dir = dbPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            dbQueue = try DatabaseQueue(path: dbPath.path)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Database setup failed: \(error)")
        }
    }

    // -------------------------------------------------------------------------------------
    // ---------------------------------- Migrations ---------------------------------------
    // -------------------------------------------------------------------------------------

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // ------------------------------------ v1 -----------------------------------------

        migrator.registerMigration("v1") { db in

            // Projects table

            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("order", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            // Tasks table

            try db.create(table: "task") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).notNull().references("project", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("isProjectManager", .boolean).notNull().defaults(to: false)
                t.column("isFinished", .boolean).notNull().defaults(to: false)
                t.column("status", .text).notNull().defaults(to: "inactive")
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("completedAt", .datetime)
            }
            try db.create(index: "task_projectId", on: "task", columns: ["projectId"])
            try db.create(index: "task_finished", on: "task", columns: ["isFinished", "createdAt"])

            // Criteria table

            try db.create(table: "criterion") { t in
                t.primaryKey("id", .text)
                t.column("taskId", .text).notNull().references("task", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("isValidated", .boolean).notNull().defaults(to: false)
                t.column("isHumanValidated", .boolean).notNull().defaults(to: false)
                t.column("order", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "criterion_taskId", on: "criterion", columns: ["taskId"])

            // Messages table

            try db.create(table: "message") { t in
                t.primaryKey("id", .text)
                t.column("taskId", .text).notNull().references("task", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("text", .text).notNull()
                t.column("timestamp", .datetime).notNull()
            }
            try db.create(index: "message_taskId", on: "message", columns: ["taskId", "timestamp"])

            // Task logs table

            try db.create(table: "taskLog") { t in
                t.primaryKey("id", .text)
                t.column("taskId", .text).notNull().references("task", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("message", .text).notNull()
                t.column("details", .text)
                t.column("timestamp", .datetime).notNull()
            }
            try db.create(index: "taskLog_taskId", on: "taskLog", columns: ["taskId", "timestamp"])

            // Artifacts table

            try db.create(table: "artifact") { t in
                t.primaryKey("id", .text)
                t.column("taskId", .text).notNull().references("task", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("label", .text).notNull()
                t.column("file", .text).notNull().defaults(to: "")
                t.column("path", .text)
                t.column("description", .text)
                t.column("order", .integer).notNull().defaults(to: 0)
                t.column("maxRows", .integer)
                t.column("items", .text)
            }
            try db.create(index: "artifact_taskId", on: "artifact", columns: ["taskId"])

            // App state table

            try db.create(table: "appState") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        // ------------------------------------ v2 -----------------------------------------

        migrator.registerMigration("v2") { db in
            try db.alter(table: "message") { t in
                t.add(column: "persona", .text).notNull().defaults(to: "manager")
            }
        }

        // ------------------------------------ v3 -----------------------------------------

        migrator.registerMigration("v3") { db in
            try db.alter(table: "project") { t in
                t.add(column: "description", .text).notNull().defaults(to: "")
            }
        }

        // ------------------------------------ v4 -----------------------------------------

        migrator.registerMigration("v4") { db in
            try db.alter(table: "project") { t in
                t.add(column: "sourceUrl", .text).notNull().defaults(to: "")
            }
        }

        // ------------------------------------ v5 -----------------------------------------

        migrator.registerMigration("v5") { db in
            try db.alter(table: "project") { t in
                t.add(column: "localPath", .text).notNull().defaults(to: "")
            }
        }

        // ------------------------------------ v6 -----------------------------------------

        migrator.registerMigration("v6") { db in
            try db.alter(table: "artifact") { t in
                t.add(column: "language", .text)
                t.add(column: "cachedHighlight", .text)
            }
        }

        // ------------------------------------ v7 -----------------------------------------

        migrator.registerMigration("v7") { db in
            try db.create(table: "engineer_criterion", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("projectId", .text).notNull().references("project", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("isCompleted", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
                t.column("order", .integer).notNull().defaults(to: 0)
            }
        }

        // ------------------------------------ v8 -----------------------------------------

        migrator.registerMigration("v8") { db in
            try db.alter(table: "artifact") { t in
                t.add(column: "caption", .text)
            }
        }

        // ------------------------------------ v9 -----------------------------------------

        migrator.registerMigration("v9") { db in
            try db.alter(table: "engineer_criterion") { t in
                t.add(column: "isHumanValidated", .boolean).defaults(to: false)
            }
        }

        // ------------------------------------ v10 ----------------------------------------

        migrator.registerMigration("v10") { db in

            // File claims table for parallel agent coordination

            try db.create(table: "file_claim") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).notNull().references("project", onDelete: .cascade)
                t.column("agentId", .text).notNull().references("task", onDelete: .cascade)
                t.column("filePath", .text).notNull()
                t.column("claimedAt", .datetime).notNull()
            }
            try db.create(index: "file_claim_project", on: "file_claim", columns: ["projectId"])
            try db.create(index: "file_claim_agent", on: "file_claim", columns: ["agentId"])
            try db.create(index: "file_claim_path", on: "file_claim", columns: ["projectId", "filePath"], unique: true)
        }

        return migrator
    }

    // MARK: - Database Access

    var reader: DatabaseReader { dbQueue }
    var writer: DatabaseWriter { dbQueue }

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
}
