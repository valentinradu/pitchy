import XCTest
@testable import Pitchy

final class PitchyTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Pitchy().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
