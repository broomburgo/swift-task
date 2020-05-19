// MARK: - Task

public struct Task<Success, Failure: Error, Progress, Environment> {
  private typealias Generic<S, F: Error, P, E> = Task<S, F, P, E>

  public enum Step {
    case ongoing(Progress)
    case completed(Result<Success, Failure>)
  }

  public struct Execute {
    private var run: (Environment) -> Void
    fileprivate init(_ run: @escaping (Environment) -> Void) {
      self.run = run
    }

    public func callAsFunction(environment: Environment) {
      run(environment)
    }
  }

  private var run: (Environment, @escaping (Step) -> Void) -> Void
  public init(_ run: @escaping (Environment, @escaping (Step) -> Void) -> Void) {
    self.run = run
  }

  public func callAsFunction(environment: Environment, callback: @escaping (Step) -> Void) {
    run(environment, callback)
  }

  public func ready(_ callback: @escaping (Step) -> Void) -> Execute {
    Execute { self.run($0, callback) }
  }
}

extension Task where Environment == Any {
  public func callAsFunction(callback: @escaping (Step) -> Void) {
    run((), callback)
  }
}

extension Task.Execute where Environment == Any {
  public func callAsFunction() {
    run(())
  }
}

public typealias Async<Success> = Task<Success, Never, Never, Any>
public typealias FailableAsync<Success, Failure: Error> = Task<Success, Failure, Never, Any>

public typealias Future<Success, Failure: Error, Environment> = Task<Success, Failure, Never, Environment>
public typealias UnboundFuture<Success, Failure: Error> = Task<Success, Failure, Never, Any>

public typealias Signal<Success, Failure: Error, Environment> = Task<Success, Failure, Success, Environment>
public typealias UnboundSignal<Success, Failure: Error> = Task<Success, Failure, Success, Any>

public typealias UnboundTask<Success, Failure: Error, Progress> = Task<Success, Failure, Progress, Any>

// MARK: - Combinators

extension Task {
  public func pullback<OtherSuccess, OtherFailure: Error, OtherProgress, OtherEnvironment>(
    success: @escaping (OtherEnvironment, Success) -> OtherSuccess,
    failure: @escaping (OtherEnvironment, Failure) -> OtherFailure,
    progress: @escaping (OtherEnvironment, Progress) -> OtherProgress,
    environment: @escaping (OtherEnvironment) -> Environment
  ) -> Task<OtherSuccess, OtherFailure, OtherProgress, OtherEnvironment> {
    Generic { otherEnvironment, yield in
      self.run(environment(otherEnvironment)) { step in
        switch step {
        case let .ongoing(x):
          yield(.ongoing(progress(otherEnvironment, x)))

        case let .completed(x):
          yield(
            .completed(x
              .map { success(otherEnvironment, $0) }
              .mapError { failure(otherEnvironment, $0) }
            )
          )
        }
      }
    }
  }

  public func changingSuccess<OtherSuccess>(
    _ transform: @escaping (Environment, Success) -> OtherSuccess
  ) -> Task<OtherSuccess, Failure, Progress, Environment> {
    pullback(
      success: transform,
      failure: getSecond,
      progress: getSecond,
      environment: identity
    )
  }

  public func changingFailure<OtherFailure: Error>(
    _ transform: @escaping (Environment, Failure) -> OtherFailure
  ) -> Task<Success, OtherFailure, Progress, Environment> {
    pullback(
      success: getSecond,
      failure: transform,
      progress: getSecond,
      environment: identity
    )
  }

  public func changingProgress<OtherProgress>(
    _ transform: @escaping (Environment, Progress) -> OtherProgress
  ) -> Task<Success, Failure, OtherProgress, Environment> {
    pullback(
      success: getSecond,
      failure: getSecond,
      progress: transform,
      environment: identity
    )
  }

  public func changingEnvironment<OtherEnvironment>(
    _ transform: @escaping (OtherEnvironment) -> Environment
  ) -> Task<Success, Failure, Progress, OtherEnvironment> {
    pullback(
      success: getSecond,
      failure: getSecond,
      progress: getSecond,
      environment: transform
    )
  }

  public static func succeeded(_ value: Success) -> Self {
    Generic { _, yield in
      yield(.completed(.success(value)))
    }
  }

  public func flatMapSuccess<OtherSuccess>(
    _ transform: @escaping (Success) -> Task<OtherSuccess, Failure, Progress, Environment>
  ) -> Task<OtherSuccess, Failure, Progress, Environment> {
    Generic { environment, yield in
      self.run(environment) { step in
        switch step {
        case let .ongoing(x):
          yield(.ongoing(x))

        case let .completed(.failure(x)):
          yield(.completed(.failure(x)))

        case let .completed(.success(x)):
          transform(x).run(environment, yield)
        }
      }
    }
  }

  public func mapSuccess<OtherSuccess>(
    _ transform: @escaping (Success) -> OtherSuccess
  ) -> Task<OtherSuccess, Failure, Progress, Environment> {
    flatMapSuccess { .succeeded(transform($0)) }
  }

  public static func failed(_ value: Failure) -> Self {
    Generic { _, yield in
      yield(.completed(.failure(value)))
    }
  }

  public func flatMapFailure<OtherFailure: Error>(
    _ transform: @escaping (Failure) -> Task<Success, OtherFailure, Progress, Environment>
  ) -> Task<Success, OtherFailure, Progress, Environment> {
    Generic { environment, yield in
      self.run(environment) { step in
        switch step {
        case let .ongoing(x):
          yield(.ongoing(x))

        case let .completed(.success(x)):
          yield(.completed(.success(x)))

        case let .completed(.failure(x)):
          transform(x).run(environment, yield)
        }
      }
    }
  }

  public func mapFailure<OtherFailure: Error>(
    _ transform: @escaping (Failure) -> OtherFailure
  ) -> Task<Success, OtherFailure, Progress, Environment> {
    flatMapFailure { .failed(transform($0)) }
  }

  public func or(_ other: @escaping @autoclosure () -> Self) -> Self {
    flatMapFailure { _ in other() }
  }

  public static func zip<A, B>(
    _ t1: Task<A, Failure, Progress, Environment>,
    _ t2: Task<B, Failure, Progress, Environment>,
    uniquingFailuresWith mergeFailures: @escaping (Failure, Failure) -> Failure
  ) -> Self where Success == (A, B) {
    Generic { environment, yield in
      var t1Result: Result<A, Failure>? {
        didSet {
          yieldIfPossible(t1Result, t2Result)
        }
      }

      var t2Result: Result<B, Failure>? {
        didSet {
          yieldIfPossible(t1Result, t2Result)
        }
      }

      t1.run(environment) { step in
        switch step {
        case let .ongoing(x):
          yield(.ongoing(x))

        case let .completed(x):
          t1Result = x
        }
      }

      t2.run(environment) { step in
        switch step {
        case let .ongoing(x):
          yield(.ongoing(x))

        case let .completed(x):
          t2Result = x
        }
      }

      func yieldIfPossible(_ t1Result: Result<A, Failure>?, _ t2Result: Result<B, Failure>?) {
        switch (t1Result, t2Result) {
        case let (.success(s1)?, .success(s2)?):
          yield(.completed(.success((s1, s2))))

        case let (.failure(f1)?, .failure(f2)?):
          yield(.completed(.failure(mergeFailures(f1, f2))))

        case let (.failure(f)?, _),
             let (_, .failure(f)?):
          yield(.completed(.failure(f)))

        case (nil, _),
             (_, nil):
          break
        }
      }
    }
  }
}

extension Task where Failure == Never {
  public func settingFailureType<Forced: Error>(to _: Forced.Type) -> Task<Success, Forced, Progress, Environment> {
    changingFailure { absurd($1) }
  }
}

extension Task where Progress == Never {
  public func settingProgressType<Forced>(to _: Forced.Type) -> Task<Success, Failure, Forced, Environment> {
    changingProgress { absurd($1) }
  }
}

extension Task where Environment == Any {
  public func settingEnvironmentType<Forced>(to _: Forced.Type) -> Task<Success, Failure, Progress, Forced> {
    changingEnvironment(identity)
  }
}

// MARK: - Canceling

public struct UniqueCancel: Equatable, Hashable {
  private let id: AnyHashable
  public let run: () -> Void

  public init(
    id: AnyHashable,
    run: @escaping () -> Void
  ) {
    self.id = id
    self.run = run
  }

  public func callAsFunction() {
    run()
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

public final class UniqueCancelBag {
  private var cancels: Set<UniqueCancel> = []

  public func add(_ cancel: UniqueCancel) {
    if let cancelPrevious = cancels.remove(cancel) {
      cancelPrevious()
    }

    cancels.insert(cancel)
  }

  deinit {
    cancels.forEach { $0() }
  }
}

public enum CancelableOngoing<Progress> {
  case start(UniqueCancel)
  case next(Progress)
}

public enum CancelableValue<Success> {
  case canceled
  case done(Success)
}

public typealias CancelableFuture<Success, Failure: Error, Progress, Environment> = Task<CancelableValue<Success>, Failure, CancelableOngoing<Progress>, Environment>
public typealias CancelableUnboundFuture<Success, Failure: Error, Progress> = Task<CancelableValue<Success>, Failure, CancelableOngoing<Progress>, Any>

public typealias CancelableSignal<Success, Failure: Error, Environment> = Task<CancelableValue<Success>, Failure, CancelableOngoing<Success>, Environment>
public typealias CancelableUnboundSignal<Success, Failure: Error> = Task<CancelableValue<Success>, Failure, CancelableOngoing<Success>, Any>

public typealias CancelableTask<Success, Failure: Error, Progress, Environment> = Task<CancelableValue<Success>, Failure, CancelableOngoing<Progress>, Environment>
public typealias CancelableUnboundTask<Success, Failure: Error, Progress> = Task<CancelableValue<Success>, Failure, CancelableOngoing<Progress>, Any>

// MARK: - Private

private func identity<A>(_ x: A) -> A { x }
private func getSecond<A, B>(_: A, _ b: B) -> B { b }
private func absurd<A>(_: Never) -> A {}
