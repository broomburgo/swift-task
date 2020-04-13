public struct Task<Success, Failure: Error, Canceling, Progress, Environment> {
  public enum Step {
    case cancelable(Canceling)
    case ongoing(Progress)
    case completed(Result<Success, Failure>)
  }

  public let run: (Environment, @escaping (Step) -> Void) -> Void
  public init(run: @escaping (Environment, @escaping (Step) -> Void) -> Void) {
    self.run = run
  }

  public func callAsFunction(environment: Environment, callback: @escaping (Step) -> Void) {
    run(environment, callback)
  }

  public func ready(_ callback: @escaping (Step) -> Void) -> (Environment) -> Void {
    { self.run($0, callback) }
  }
}

public typealias Async<Success> = Task<Success, Never, Never, Never, Any>
public typealias FailableAsync<Success, Failue: Error> = Task<Success, Failue, Never, Never, Any>

public typealias Future<Success, Failure: Error, Canceling, Environment> = Task<Success, Failure, Canceling, Never, Environment>
public typealias UnboundFuture<Success, Failure: Error, Canceling> = Task<Success, Failure, Canceling, Never, Any>

public typealias Signal<Success, Failure: Error, Canceling, Environment> = Task<Success, Failure, Canceling, Success, Environment>
public typealias UnboundSignal<Success, Failure: Error, Canceling> = Task<Success, Failure, Canceling, Success, Any>

public typealias UnboundTask<Success, Failure: Error, Canceling, Progress> = Task<Success, Failure, Canceling, Progress, Any>

public func identity<A>(_ x: A) -> A { x }
public func absurd(_ never: Never) -> Never {}

extension Task where Environment == Any {
  public func ready(_ callback: @escaping (Step) -> Void) -> () -> Void {
    { self.run((), callback) }
  }
}

extension Task {
  public func map<OtherSuccess, OtherFailure: Error, OtherCanceling, OtherProgress>(
    success: @escaping (Success) -> OtherSuccess,
    failure: @escaping (Failure) -> OtherFailure,
    canceling: @escaping (Canceling) -> OtherCanceling,
    progress: @escaping (Progress) -> OtherProgress
  ) -> Task<OtherSuccess, OtherFailure, OtherCanceling, OtherProgress, Environment> {
    .init { environment, yield in
      self.run(environment) { step in
        switch step {
        case let .cancelable(x):
          yield(.cancelable(canceling(x)))

        case let .ongoing(x):
          yield(.ongoing(progress(x)))

        case let .completed(x):
          yield(.completed(x.map(success).mapError(failure)))
        }
      }
    }
  }

  public func mapSuccess<OtherSuccess>(
    _ transform: @escaping (Success) -> OtherSuccess
  ) -> Task<OtherSuccess, Failure, Canceling, Progress, Environment> {
    map(success: transform, failure: identity, canceling: identity, progress: identity)
  }

  public func mapFailure<OtherFailure: Error>(
    transform: @escaping (Failure) -> OtherFailure
  ) -> Task<Success, OtherFailure, Canceling, Progress, Environment> {
    map(success: identity, failure: transform, canceling: identity, progress: identity)
  }

  public func mapCanceling<OtherCanceling>(
    transform: @escaping (Canceling) -> OtherCanceling
  ) -> Task<Success, Failure, OtherCanceling, Progress, Environment> {
    map(success: identity, failure: identity, canceling: transform, progress: identity)
  }

  public func mapProgress<OtherProgress>(
    transform: @escaping (Progress) -> OtherProgress
  ) -> Task<Success, Failure, Canceling, OtherProgress, Environment> {
    map(success: identity, failure: identity, canceling: identity, progress: transform)
  }

  public func pullback<OtherEnvironment>(
    _ transform: @escaping (OtherEnvironment) -> Environment
  ) -> Task<Success, Failure, Canceling, Progress, OtherEnvironment> {
    .init { otherEnvironment, yield in
      self.run(transform(otherEnvironment)) { step in
        switch step {
        case let .cancelable(x):
          yield(.cancelable(x))

        case let .ongoing(x):
          yield(.ongoing(x))

        case let .completed(x):
          yield(.completed(x))
        }
      }
    }
  }

  public typealias Generic<A> = Task<A, Failure, Canceling, Progress, Environment>

  public static func zip<A, B>(
    _ t1: Generic<A>,
    _ t2: Generic<B>,
    uniquingFailuresWith mergeFailures: @escaping (Failure, Failure) -> Failure
  ) -> Self where Success == (A, B) {
    .init { environment, yield in
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
        case let .cancelable(x):
          yield(.cancelable(x))

        case let .ongoing(x):
          yield(.ongoing(x))

        case let .completed(x):
          t1Result = x
        }
      }

      t2.run(environment) { step in
        switch step {
        case let .cancelable(x):
          yield(.cancelable(x))

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

  public func flatMapSuccess<OtherSuccess>(
    _ transform: @escaping (Success) -> Task<OtherSuccess, Failure, Canceling, Progress, Environment>
  ) -> Task<OtherSuccess, Failure, Canceling, Progress, Environment> {
    .init { environment, yield in
      self.run(environment) { step in
        switch step {
        case let .cancelable(x):
          yield(.cancelable(x))

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

  public func flatMapFailure<OtherFailure: Error>(
    _ transform: @escaping (Failure) -> Task<Success, OtherFailure, Canceling, Progress, Environment>
  ) -> Task<Success, OtherFailure, Canceling, Progress, Environment> {
    .init { environment, yield in
      self.run(environment) { step in
        switch step {
        case let .cancelable(x):
          yield(.cancelable(x))

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

  public func or(_ other: @escaping @autoclosure () -> Self) -> Self {
    flatMapFailure { _ in other() }
  }
}
