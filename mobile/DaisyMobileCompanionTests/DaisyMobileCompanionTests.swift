import XCTest
@testable import DaisyMobileCompanion

final class DaisyMobileCompanionTests: XCTestCase {

    func testProjectInit() {
        let project = Project(name: "Test Project", description: "A test")
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.description, "A test")
        XCTAssertFalse(project.id.isEmpty)
    }

    func testTaskInit() {
        let task = ProjectTask(projectId: "p1", title: "Test Task")
        XCTAssertEqual(task.title, "Test Task")
        XCTAssertEqual(task.status, "inactive")
        XCTAssertFalse(task.isFinished)
    }

    func testCriterionInit() {
        let criterion = Criterion(taskId: "t1", text: "Must pass tests")
        XCTAssertEqual(criterion.text, "Must pass tests")
        XCTAssertFalse(criterion.isVerified)
    }
}
