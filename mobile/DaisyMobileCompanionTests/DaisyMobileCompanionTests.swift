import XCTest
@testable import DaisyMobileCompanion

final class DaisyMobileCompanionTests: XCTestCase {

    func testProjectInit() {
        let project = Project(name: "Test Project", description: "A test")
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.description, "A test")
        XCTAssertFalse(project.id.isEmpty)
    }

    func testAgentInit() {
        let agent = Agent(projectId: "p1", title: "Test Agent")
        XCTAssertEqual(agent.title, "Test Agent")
        XCTAssertEqual(agent.status, "inactive")
        XCTAssertFalse(agent.isFinished)
        XCTAssertFalse(agent.isDefault)
    }

    func testCriterionInit() {
        let criterion = Criterion(taskId: "t1", text: "Must pass tests")
        XCTAssertEqual(criterion.text, "Must pass tests")
        XCTAssertFalse(criterion.isValidated)
    }

    func testMessageInit() {
        let message = Message(agentId: "a1", role: "user", text: "Hello")
        XCTAssertEqual(message.text, "Hello")
        XCTAssertTrue(message.isUser)
        XCTAssertFalse(message.isAgent)
    }

    func testAppConfig() {
        XCTAssertFalse(AppConfig.serverAddress.isEmpty)
        XCTAssertTrue(AppConfig.baseURL.hasPrefix("http://"))
    }
}
