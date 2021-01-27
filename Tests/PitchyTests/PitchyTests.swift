import XCTest
@testable import Pitchy


final class PitchyTests: XCTestCase {
    func testFreqUpdates() throws {
        let expect = XCTestExpectation(description: "Receive freq updates")
        let pitchy = try Pitchy()
        try pitchy.start { freq in
            if let freq = freq {
                XCTAssertGreaterThan(freq, 0)
            }
            expect.fulfill()
        }
        wait(for: [expect], timeout: 20)
        try pitchy.stop()
    }

    static var allTests = [
        ("Basic", testFreqUpdates),
    ]
}
