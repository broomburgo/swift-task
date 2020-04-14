public struct Task<Success, Failure: Error, Progress, Environment> {
  public enum Step {
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

public typealias Async<Success> = Task<Success, Never, Never, Any>
public typealias FailableAsync<Success, Failure: Error> = Task<Success, Failure, Never, Any>

public typealias Future<Success, Failure: Error, Environment> = Task<Success, Failure, Never, Environment>
public typealias UnboundFuture<Success, Failure: Error> = Task<Success, Failure, Never, Any>

public typealias Signal<Success, Failure: Error, Environment> = Task<Success, Failure, Success, Environment>
public typealias UnboundSignal<Success, Failure: Error> = Task<Success, Failure, Success, Any>

public typealias UnboundTask<Success, Failure: Error, Progress> = Task<Success, Failure, Progress, Any>

extension Task where Environment == Any {
  public func ready(_ callback: @escaping (Step) -> Void) -> () -> Void {
    { self.run((), callback) }
  }
}

extension Task {
  public func map<OtherSuccess, OtherFailure: Error, OtherProgress>(
    success: @escaping (Success) -> OtherSuccess,
    failure: @escaping (Failure) -> OtherFailure,
    progress: @escaping (Progress) -> OtherProgress
  ) -> Task<OtherSuccess, OtherFailure, OtherProgress, Environment> {
    .init { environment, yield in
      self.run(environment) { step in
        switch step {
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
  ) -> Task<OtherSuccess, Failure, Progress, Environment> {
    map(success: transform, failure: identity, progress: identity)
  }

  public func mapFailure<OtherFailure: Error>(
    _ transform: @escaping (Failure) -> OtherFailure
  ) -> Task<Success, OtherFailure, Progress, Environment> {
    map(success: identity, failure: transform, progress: identity)
  }

  public func mapProgress<OtherProgress>(
    _ transform: @escaping (Progress) -> OtherProgress
  ) -> Task<Success, Failure, OtherProgress, Environment> {
    map(success: identity, failure: identity, progress: transform)
  }

  public func pullback<OtherEnvironment>(
    _ transform: @escaping (OtherEnvironment) -> Environment
  ) -> Task<Success, Failure, Progress, OtherEnvironment> {
    .init { otherEnvironment, yield in
      self.run(transform(otherEnvironment)) { step in
        switch step {
        case let .ongoing(x):
          yield(.ongoing(x))

        case let .completed(x):
          yield(.completed(x))
        }
      }
    }
  }

  public static func zip<A, B>(
    _ t1: Task<A, Failure, Progress, Environment>,
    _ t2: Task<B, Failure, Progress, Environment>,
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

  public func flatMapSuccess<OtherSuccess>(
    _ transform: @escaping (Success) -> Task<OtherSuccess, Failure, Progress, Environment>
  ) -> Task<OtherSuccess, Failure, Progress, Environment> {
    .init { environment, yield in
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

  public func flatMapFailure<OtherFailure: Error>(
    _ transform: @escaping (Failure) -> Task<Success, OtherFailure, Progress, Environment>
  ) -> Task<Success, OtherFailure, Progress, Environment> {
    .init { environment, yield in
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

  public func or(_ other: @escaping @autoclosure () -> Self) -> Self {
    flatMapFailure { _ in other() }
  }
}

extension Task where Failure == Never {
  public func settingFailureType<Forced: Error>(to _: Forced.Type) -> Task<Success, Forced, Progress, Environment> {
    mapFailure(absurd)
  }
}

extension Task where Progress == Never {
  public func settingProgressType<Forced>(to _: Forced.Type) -> Task<Success, Failure, Forced, Environment> {
    mapProgress(absurd)
  }
}

extension Task where Environment == Any {
  public func settingEnvironmentType<Forced>(to _: Forced.Type) -> Task<Success, Failure, Progress, Forced> {
    pullback(identity)
  }
}

public struct UniqueCancel: Equatable, Hashable {
  public let id: AnyHashable
  public let cancel: () -> Void

  public init(
    id: AnyHashable,
    cancel: @escaping () -> Void
  ) {
    self.id = id
    self.cancel = cancel
  }

  public func callAsFunction() {
    cancel()
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
    if let previous = cancels.remove(cancel) {
      previous.cancel()
    }

    cancels.insert(cancel)
  }

  deinit {
    cancels.forEach { $0.cancel() }
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
private func absurd<A>(_ never: Never) -> A {}
