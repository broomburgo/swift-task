@testable import SwiftTask
import XCTest

extension String: Error {}
private typealias LocalResult = Result<Int, String>
private typealias LocalTask = Task<Int, String, Never, Any>
private typealias LocalUnfailableTask = Task<Int, Never, Never, Any>
private typealias LocalTaskWithEnv = Task<Int, String, Never, Bool>
private typealias LocalTaskWithProgress = Task<Int, String, Double, Any>

final class SwiftTaskTests: XCTestCase {
  func testCompletedTaskYieldsProperResult() {
    let expectedResult = LocalResult.success(42)

    let task = LocalTask(completed: expectedResult)

    var gotResult: LocalResult?
    task(onCompleted: {
      gotResult = $0
    })

    XCTAssertEqual(gotResult, expectedResult)
  }

  func testSuccessfulTaskYieldsProperResult() {
    let expectedValue = 42

    let task = LocalUnfailableTask.init(completed: .success(expectedValue))

    var gotValue: Int?
    task(onSuccess: {
      gotValue = $0
    })

    XCTAssertEqual(gotValue, expectedValue)
  }

  func testCompletedTaskWithEnvYieldsProperResult() {
    let expectedEnv = true
    let expectedResult = LocalResult.success(42)

    let task = LocalTaskWithEnv { env, step in
      XCTAssertEqual(env, expectedEnv)
      step(.completed(expectedResult))
    }

    var gotResult: LocalResult?
    task(
      environment: expectedEnv,
      onCompleted: {
        gotResult = $0
      }
    )

    XCTAssertEqual(gotResult, expectedResult)
  }

  func testMapSuccessWithSuccess() {
    let value = 42
    let successfulResult = LocalResult.success(value)
    let successfulTask = LocalTask(completed: successfulResult)
    let mappedTask = successfulTask.mapSuccess { $0 + 1 }

    var gotResult: LocalResult?
    mappedTask(onCompleted: {
      gotResult = $0
    })

    XCTAssertEqual(gotResult, .success(value + 1))
  }

  func testMapSuccessWithFailure() {
    let error = "howdy"
    let failedResult = LocalResult.failure(error)
    let failedTask = LocalTask(completed: failedResult)
    let unmappedTask = failedTask.mapSuccess { $0 + 1 }

    var gotResult: LocalResult?
    unmappedTask(onCompleted: {
      gotResult = $0
    })

    XCTAssertEqual(gotResult, .failure(error))
  }

  func testMapFailureWithSuccess() {
    let value = 42
    let successfulResult = LocalResult.success(value)
    let successfulTask = LocalTask(completed: successfulResult)
    let unmappedTask = successfulTask.mapFailure { $0 + "!" }

    var gotResult: LocalResult?
    unmappedTask(onCompleted: {
      gotResult = $0
    })

    XCTAssertEqual(gotResult, .success(value))
  }

  func testMapFailureWithFailure() {
    let error = "howdy"
    let failedResult = LocalResult.failure(error)
    let failedTask = LocalTask(completed: failedResult)
    let mappedTask = failedTask.mapFailure { $0 + "!" }

    var gotResult: LocalResult?
    mappedTask(onCompleted: {
      gotResult = $0
    })

    XCTAssertEqual(gotResult, .failure(error + "!"))
  }

  func testMapProgress() {
    let error = "howdy"
    let progress = 21.0
    let task = LocalTaskWithProgress { _, yield in
      yield(.ongoing(progress))
      yield(.completed(.failure(error)))
    }

    let mappedTask = task.mapProgress { $0 * 2 }

    var gotProgress: Double?
    mappedTask(onStep: {
      switch $0 {
      case .ongoing(let progress):
        gotProgress = progress

      case .completed:
        break
      }
    })

    XCTAssertEqual(gotProgress, progress * 2)
  }

  func testMapEnvironment() {
    let value = 1
    let task = LocalTaskWithEnv { env, yield in
      yield(.completed(.success(env ? value : -value)))
    }

    let mappedTask = task.mapEnvironment { !$0 }

    var gotResult1: LocalResult?
    mappedTask(environment: true, onCompleted: {
      gotResult1 = $0
    })

    XCTAssertEqual(gotResult1, .success(-value))

    var gotResult2: LocalResult?
    mappedTask(environment: false, onCompleted: {
      gotResult2 = $0
    })

    XCTAssertEqual(gotResult2, .success(value))
  }

  func testFlatMapSuccess() {
    let value = 42
    let error = "howdy"

    let successTask = LocalTask(completed: .success(value))
    let failureTask = LocalTask(completed: .failure(error))

    typealias Transform = (Int) -> LocalTask

    let toSecondarySuccess: Transform = { value in
      LocalTask(completed: .success(value * 2))
    }

    let toSecondaryFailure: Transform = { value in
      LocalTask(completed: .failure("\(value)"))
    }

    var successToSuccess: LocalResult?
    successTask.flatMapSuccess(toSecondarySuccess)(onCompleted: {
      successToSuccess = $0
    })
    XCTAssertEqual(successToSuccess, .success(84))

    var successToFailure: LocalResult?
    successTask.flatMapSuccess(toSecondaryFailure)(onCompleted: {
      successToFailure = $0
    })
    XCTAssertEqual(successToFailure, .failure("42"))

    var failureToSuccess: LocalResult?
    failureTask.flatMapSuccess(toSecondarySuccess)(onCompleted: {
      failureToSuccess = $0
    })
    XCTAssertEqual(failureToSuccess, .failure("howdy"))

    var failureToFailure: LocalResult?
    failureTask.flatMapSuccess(toSecondaryFailure)(onCompleted: {
      failureToFailure = $0
    })
    XCTAssertEqual(failureToFailure, .failure("howdy"))
  }

  func testFlatMapFailure() {
    let value = 42
    let error = "howdy"

    let successTask = LocalTask(completed: .success(value))
    let failureTask = LocalTask(completed: .failure(error))

    typealias Transform = (String) -> LocalTask

    let toSecondarySuccess: Transform = { error in
      LocalTask(completed: .success(error.count))
    }

    let toSecondaryFailure: Transform = { error in
      LocalTask(completed: .failure("\(error)!"))
    }

    var successToSuccess: LocalResult?
    successTask.flatMapFailure(toSecondarySuccess)(onCompleted: {
      successToSuccess = $0
    })
    XCTAssertEqual(successToSuccess, .success(42))

    var successToFailure: LocalResult?
    successTask.flatMapFailure(toSecondaryFailure)(onCompleted: {
      successToFailure = $0
    })
    XCTAssertEqual(successToFailure, .success(42))

    var failureToSuccess: LocalResult?
    failureTask.flatMapFailure(toSecondarySuccess)(onCompleted: {
      failureToSuccess = $0
    })
    XCTAssertEqual(failureToSuccess, .success(5))

    var failureToFailure: LocalResult?
    failureTask.flatMapFailure(toSecondaryFailure)(onCompleted: {
      failureToFailure = $0
    })
    XCTAssertEqual(failureToFailure, .failure("howdy!"))
  }

  func testZipWithSuccess() {
    let s1 = LocalTask(completed: .success(1))
    let s2 = LocalTask(completed: .success(10))
    let s3 = LocalTask(completed: .success(100))

    let z1 = Task.zipWith(Task.zipWith(s1, s2, +), s3, +)
    let z2 = Task.zipWith(s1, Task.zipWith(s2, s3, +), +)
    let z3 = Task.zipWith(
      s1,
      s2,
      s3,
      { $0 + $1 + $2 }
    )

    var r1: LocalResult?
    z1(onCompleted: { r1 = $0 })

    var r2: LocalResult?
    z2(onCompleted: { r2 = $0 })

    var r3: LocalResult?
    z3(onCompleted: { r3 = $0 })

    XCTAssertEqual(r1, .success(111))
    XCTAssertEqual(r1, r2)
    XCTAssertEqual(r2, r3)
  }

  func testZipWith() {
    let s1 = LocalTask(completed: .success(1))
    let s2 = LocalTask(completed: .success(10))

    let f1 = LocalTask(completed: .failure("1"))
    let f2 = LocalTask(completed: .failure("2"))

    let ss = Task.zipWith(s1, s2, +)
    let sf = Task.zipWith(s1, f2, +)
    let fs = Task.zipWith(f1, s2, +)
    let ff = Task.zipWith(f1, f2, +, uniquingFailuresWith: +)

    var rss: LocalResult?
    ss(onCompleted: { rss = $0 })
    XCTAssertEqual(rss, .success(11))

    var rsf: LocalResult?
    sf(onCompleted: { rsf = $0 })
    XCTAssertEqual(rsf, .failure("2"))

    var rfs: LocalResult?
    fs(onCompleted: { rfs = $0 })
    XCTAssertEqual(rfs, .failure("1"))

    var rff: LocalResult?
    ff(onCompleted: { rff = $0 })
    XCTAssertEqual(rff, .failure("12"))
  }

  func testOr() {
    let s1 = LocalTask(completed: .success(1))
    let s2 = LocalTask(completed: .success(10))

    let f1 = LocalTask(completed: .failure("1"))
    let f2 = LocalTask(completed: .failure("2"))

    let ss = s1.or(s2)
    let sf = s1.or(f2)
    let fs = f1.or(s2)
    let ff = f1.or(f2)

    var rss: LocalResult?
    ss(onCompleted: { rss = $0 })
    XCTAssertEqual(rss, .success(1))

    var rsf: LocalResult?
    sf(onCompleted: { rsf = $0 })
    XCTAssertEqual(rsf, .success(1))

    var rfs: LocalResult?
    fs(onCompleted: { rfs = $0 })
    XCTAssertEqual(rfs, .success(10))

    var rff: LocalResult?
    ff(onCompleted: { rff = $0 })
    XCTAssertEqual(rff, .failure("2"))
  }

  func testFallback() {
    let s = LocalTask(completed: .success(1))
    let f = LocalTask(completed: .failure("1"))

    let sfb = s.fallback(to: 10)
    let ffb = f.fallback(to: 10)

    var rsfb: LocalResult?
    sfb(onCompleted: { rsfb = $0 })
    XCTAssertEqual(rsfb, .success(1))

    var rffb: LocalResult?
    ffb(onCompleted: { rffb = $0 })
    XCTAssertEqual(rffb, .success(10))
  }

  func testAllInSuccess() {
    let s1 = LocalTask(completed: .success(1))
    let s2 = LocalTask(completed: .success(10))
    let s3 = LocalTask(completed: .success(100))

    let ai = Task.allIn(first: s1, rest: [s2, s3]).mapSuccess { $0.reduce(0, +) }

    var r: LocalResult?
    ai(onCompleted: { r = $0 })

    XCTAssertEqual(r, .success(111))
  }

  func testAllIn() {
    let s1 = LocalTask(completed: .success(1))
    let s2 = LocalTask(completed: .success(10))
    let s3 = LocalTask(completed: .success(100))

    let f1 = LocalTask(completed: .failure("1"))
    let f2 = LocalTask(completed: .failure("2"))
    let f3 = LocalTask(completed: .failure("3"))

    let aisss = Task.allIn(first: s1, rest: [s2, s3], uniquingFailuresWith: +).mapSuccess { $0.reduce(0, +) }
    let aissf = Task.allIn(first: s1, rest: [s2, f3], uniquingFailuresWith: +).mapSuccess { $0.reduce(0, +) }
    let aisfs = Task.allIn(first: s1, rest: [f2, s3], uniquingFailuresWith: +).mapSuccess { $0.reduce(0, +) }
    let aifss = Task.allIn(first: f1, rest: [s2, s3], uniquingFailuresWith: +).mapSuccess { $0.reduce(0, +) }
    let aisff = Task.allIn(first: s1, rest: [f2, f3], uniquingFailuresWith: +).mapSuccess { $0.reduce(0, +) }
    let aifsf = Task.allIn(first: f1, rest: [s2, f3], uniquingFailuresWith: +).mapSuccess { $0.reduce(0, +) }
    let aiffs = Task.allIn(first: f1, rest: [f2, s3], uniquingFailuresWith: +).mapSuccess { $0.reduce(0, +) }
    let aifff = Task.allIn(first: f1, rest: [f2, f3], uniquingFailuresWith: +).mapSuccess { $0.reduce(0, +) }

    var sss: LocalResult?
    aisss(onCompleted: { sss = $0 })
    XCTAssertEqual(sss, .success(111))

    var ssf: LocalResult?
    aissf(onCompleted: { ssf = $0 })
    XCTAssertEqual(ssf, .failure("3"))

    var sfs: LocalResult?
    aisfs(onCompleted: { sfs = $0 })
    XCTAssertEqual(sfs, .failure("2"))

    var fss: LocalResult?
    aifss(onCompleted: { fss = $0 })
    XCTAssertEqual(fss, .failure("1"))

    var sff: LocalResult?
    aisff(onCompleted: { sff = $0 })
    XCTAssertEqual(sff, .failure("23"))

    var fsf: LocalResult?
    aifsf(onCompleted: { fsf = $0 })
    XCTAssertEqual(fsf, .failure("13"))

    var ffs: LocalResult?
    aiffs(onCompleted: { ffs = $0 })
    XCTAssertEqual(ffs, .failure("12"))

    var fff: LocalResult?
    aifff(onCompleted: { fff = $0 })
    XCTAssertEqual(fff, .failure("123"))
  }

  func testOnStepEquivalencySuccess() {
    let t1 = LocalTask(completed: .success(42))

    var r1: LocalResult?
    t1.onStep {
      switch $0 {
      case .ongoing(_):
        fatalError()

      case .completed(let result):
        r1 = result
      }
    }(onStep: { _ in })

    var r2: LocalResult?
    t1(
      onCompleted: {
        r2 = $0
      }
    )

    XCTAssertEqual(r1, .success(42))
    XCTAssertEqual(r1, r2)
  }

  func testOnStepEquivalencyFailure() {
    let t1 = LocalTask(completed: .failure("howdy"))

    var r1: LocalResult?
    t1.onStep {
        switch $0 {
        case .ongoing(_):
          fatalError()

        case .completed(let result):
          r1 = result
        }
    }(onStep: { _ in })

    var r2: LocalResult?
    t1(
      onCompleted: {
        r2 = $0
      }
    )

    XCTAssertEqual(r1, .failure("howdy"))
    XCTAssertEqual(r1, r2)
  }

  func testOnCompletedEquivalencySuccess() {
    let t1 = LocalTask(completed: .success(42))

    var r1: LocalResult?
    t1.onCompleted {
      r1 = $0
    }(onCompleted: { _ in })

    var r2: LocalResult?
    t1(
      onCompleted: {
        r2 = $0
      }
    )

    XCTAssertEqual(r1, .success(42))
    XCTAssertEqual(r1, r2)
  }

  func testOnCompletedEquivalencyFailure() {
    let t1 = LocalTask(completed: .failure("howdy"))

    var r1: LocalResult?
    t1.onCompleted {
      r1 = $0
    }(onCompleted: { _ in })

    var r2: LocalResult?
    t1(
      onCompleted: {
        r2 = $0
      }
    )

    XCTAssertEqual(r1, .failure("howdy"))
    XCTAssertEqual(r1, r2)
  }

  func testOnSuccessEquivalency() {
    let t1 = LocalUnfailableTask(completed: .success(42))

    var r1: Int?
    t1.onSuccess {
      r1 = $0
    }(onSuccess: { _ in })

    var r2: Int?
    t1(
      onSuccess: {
        r2 = $0
      }
    )

    XCTAssertEqual(r1, 42)
    XCTAssertEqual(r1, r2)
  }

  /// Add tests for cancelables

  static var allTests = [
    ("testOr", testOr),
    ("testAllIn", testAllIn),
    ("testZipWith", testZipWith),
    ("testFallback", testFallback),
    ("testMapProgress", testMapProgress),
    ("testAllInSuccess", testAllInSuccess),
    ("testFlatMapFailure", testFlatMapFailure),
    ("testFlatMapSuccess", testFlatMapSuccess),
    ("testMapEnvironment", testMapEnvironment),
    ("testZipWithSuccess", testZipWithSuccess),
    ("testMapFailureWithFailure", testMapFailureWithFailure),
    ("testMapFailureWithSuccess", testMapFailureWithSuccess),
    ("testMapSuccessWithFailure", testMapSuccessWithFailure),
    ("testMapSuccessWithSuccess", testMapSuccessWithSuccess),
    ("testOnStepEquivalencyFailure", testOnStepEquivalencyFailure),
    ("testOnStepEquivalencySuccess", testOnStepEquivalencySuccess),
    ("testOnCompletedEquivalencyFailure", testOnCompletedEquivalencyFailure),
    ("testOnCompletedEquivalencySuccess", testOnCompletedEquivalencySuccess),
    ("testCompletedTaskYieldsProperResult", testCompletedTaskYieldsProperResult),
    ("testCompletedTaskWithEnvYieldsProperResult", testCompletedTaskWithEnvYieldsProperResult)
  ]
}
