import SwiftTask
import SwiftTaskFoundation
import XCTest

extension String: Error {}
private typealias LocalResult = Result<Int, String>
private typealias LocalTask = Task<Int, String, Never, Any>
private typealias LocalTaskWithEnv = Task<Int, String, Never, Bool>
private typealias LocalTaskWithProgress = Task<Int, String, Double, Any>

final class SwiftTaskFoundationTests: XCTestCase {
  func testReceiveOnBackgroundQueue() {
    let queue = DispatchQueue(label: "testQueue")

    let task = LocalTask(completed: .success(42))

    var result: LocalResult?
    task.receive(on: queue)(onCompleted: { result = $0 })

    XCTAssertNil(result)

    let done = expectation(description: "done")
    queue.async {
      XCTAssertEqual(result, .success(42))
      done.fulfill()
    }
    wait(for: [done], timeout: 1)
  }

  static var allTests = [
    ("testReceiveOnBackgroundQueue", testReceiveOnBackgroundQueue)
  ]
}
