import XCTest
@testable import SwiftTask

final class swift_taskTests: XCTestCase {
    func testExample() {
      let expected = "Hello, world!"
      let task = Async<String>.succeeded(expected)
      
      var received: String?
      let run = task.ready {
        switch $0 {
        case let .completed(.success(value)):
          received = value
          
        case let .completed(.failure(never)),
             let .ongoing(never):
          received = absurd(never)
        }
      }
      
      run()
      XCTAssertEqual(received, expected)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

private func absurd<A>(_: Never) -> A {}
