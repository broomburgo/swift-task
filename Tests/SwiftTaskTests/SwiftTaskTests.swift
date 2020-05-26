@testable import SwiftTask
import XCTest

final class swift_taskTests: XCTestCase {
  func testExample() {
    let expected = "Hello, world!"
    let task = Async<String>(completed: .success(expected))

    var received: String?
    task.callAsFunction(onCompleted: {
      switch $0 {
      case .success(let value):
        received = value

      case .failure(let never):
        received = absurd(never)
      }
    })

    XCTAssertEqual(received, expected)
  }

  static var allTests = [
    ("testExample", testExample),
  ]
}

private func absurd<A>(_: Never) -> A {}
