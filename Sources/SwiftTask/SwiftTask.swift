// MARK: - Task

public struct Task<Success, Failure: Error, Progress, Environment> {
  private typealias Generic<S, F: Error, P, E> = Task<S, F, P, E>

  public enum Step {
    case ongoing(Progress)
    case completed(Result<Success, Failure>)
  }

  private let run: (Environment, @escaping (Step) -> Void) -> Void
  public init(_ run: @escaping (Environment, @escaping (Step) -> Void) -> Void) {
    self.run = run
  }

  public init(completed result: Result<Success, Failure>) {
    self.run = { $1(.completed(result)) }
  }

  public func callAsFunction(environment: Environment, onStep: @escaping (Step) -> Void) {
    run(environment, onStep)
  }

  public func onStep(_ callback: @escaping (Step) -> Void) -> Self {
    Self { environment, yield in
      self.run(environment) { step in
        callback(step)
        yield(step)
      }
    }
  }
}

extension Task where Progress == Never {
  public func callAsFunction(environment: Environment, onCompleted: @escaping (Result<Success, Failure>) -> Void) {
    run(environment) { step in
      switch step {
      case let .ongoing(x):
        impossible(x)

      case let .completed(result):
        onCompleted(result)
      }
    }
  }

  public func onCompleted(_ callback: @escaping (Result<Success, Failure>) -> Void) -> Self {
    Self { environment, yield in
      self(environment: environment, onCompleted: { result in
        callback(result)
        yield(.completed(result))
      })
    }
  }
}

extension Task where Failure == Never, Progress == Never {
  public func callAsFunction(environment: Environment, onSuccess: @escaping (Success) -> Void) {
    run(environment) { step in
      switch step {
      case let .ongoing(x),
           let .completed(.failure(x)):
        impossible(x)

      case let .completed(.success(value)):
        onSuccess(value)
      }
    }
  }

  public func onSuccess(_ callback: @escaping (Success) -> Void) -> Self {
    Self { environment, yield in
      self(environment: environment, onSuccess: { value in
        callback(value)
        yield(.completed(.success(value)))
      })
    }
  }
}

extension Task where Environment == Any {
  public func callAsFunction(onStep: @escaping (Step) -> Void) {
    run((), onStep)
  }
}

extension Task where Progress == Never, Environment == Any {
  public func callAsFunction(onCompleted: @escaping (Result<Success, Failure>) -> Void) {
    self(environment: (), onCompleted: onCompleted)
  }
}

extension Task where Failure == Never, Progress == Never, Environment == Any {
  public func callAsFunction(onSuccess: @escaping (Success) -> Void) {
    self(environment: (), onSuccess: onSuccess)
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
      failure: { $1 },
      progress: { $1 },
      environment: { $0 }
    )
  }

  public func mapSuccess<OtherSuccess>(
    _ transform: @escaping (Success) -> OtherSuccess
  ) -> Task<OtherSuccess, Failure, Progress, Environment> {
    changingSuccess { transform($1) }
  }

  public func changingFailure<OtherFailure: Error>(
    _ transform: @escaping (Environment, Failure) -> OtherFailure
  ) -> Task<Success, OtherFailure, Progress, Environment> {
    pullback(
      success: { $1 },
      failure: transform,
      progress: { $1 },
      environment: { $0 }
    )
  }

  public func mapFailure<OtherFailure: Error>(
    _ transform: @escaping (Failure) -> OtherFailure
  ) -> Task<Success, OtherFailure, Progress, Environment> {
    changingFailure { transform($1) }
  }

  public func changingProgress<OtherProgress>(
    _ transform: @escaping (Environment, Progress) -> OtherProgress
  ) -> Task<Success, Failure, OtherProgress, Environment> {
    pullback(
      success: { $1 },
      failure: { $1 },
      progress: transform,
      environment: { $0 }
    )
  }

  public func mapProgress<OtherProgress>(
    _ transform: @escaping (Progress) -> OtherProgress
  ) -> Task<Success, Failure, OtherProgress, Environment> {
    changingProgress { transform($1) }
  }

  public func mapEnvironment<OtherEnvironment>(
    _ transform: @escaping (OtherEnvironment) -> Environment
  ) -> Task<Success, Failure, Progress, OtherEnvironment> {
    pullback(
      success: { $1 },
      failure: { $1 },
      progress: { $1 },
      environment: transform
    )
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

  public func or(_ other: @escaping @autoclosure () -> Self) -> Self {
    flatMapFailure { _ in other() }
  }

  public func fallback(to value: @escaping @autoclosure () -> Success) -> Self {
    or(.init(completed: .success(value())))
  }

  public static func zipWith<A, B>(
    _ t1: Task<A, Failure, Progress, Environment>,
    _ t2: Task<B, Failure, Progress, Environment>,
    _ transform: @escaping (A, B) -> Success,
    uniquingFailuresWith mergeFailures: @escaping (Failure, Failure) -> Failure = { a, _ in a }
  ) -> Self {
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
        guard
          let t1Result = t1Result,
          let t2Result = t2Result
        else {
          return
        }

        switch (t1Result, t2Result) {
        case let (.success(s1), .success(s2)):
          yield(.completed(.success(transform(s1, s2))))

        case let (.failure(f1), .failure(f2)):
          yield(.completed(.failure(mergeFailures(f1, f2))))

        case let (.failure(f), .success(_)),
             let (.success(_), .failure(f)):
          yield(.completed(.failure(f)))
        }
      }
    }
  }

  public static func zipWith<A, B, C>(
    _ t1: Task<A, Failure, Progress, Environment>,
    _ t2: Task<B, Failure, Progress, Environment>,
    _ t3: Task<C, Failure, Progress, Environment>,
    _ transform: @escaping (A, B, C) -> Success,
    uniquingFailuresWith mergeFailures: @escaping (Failure, Failure) -> Failure = { a, _ in a }
  ) -> Self {
    zipWith(
      t1,
      Generic.zipWith(
        t2,
        t3,
        { ($0, $1) },
        uniquingFailuresWith: mergeFailures
      ),
      { a, bc in
        transform(a, bc.0, bc.1)
      },
      uniquingFailuresWith: mergeFailures
    )
  }

  public static func allIn<A, S>(
    first: Task<A, Failure, Progress, Environment>,
    rest: S,
    uniquingFailuresWith mergeFailures: @escaping (Failure, Failure) -> Failure = { a, _ in a }
  ) -> Self where
    S: Sequence,
    S.Element == Task<A, Failure, Progress, Environment>,
    Success == [A] {
    rest.reduce(first.mapSuccess { [$0] }) {
      Generic.zipWith(
        $0,
        $1,
        {
          var m = $0
          m.append($1)
          return m
        },
        uniquingFailuresWith: mergeFailures
      )
    }
  }
}

extension Task where Failure == Never {
  public func settingFailureType<Forced: Error>(to _: Forced.Type) -> Task<Success, Forced, Progress, Environment> {
    mapFailure { impossible($0) }
  }
}

extension Task where Progress == Never {
  public func settingProgressType<Forced>(to _: Forced.Type) -> Task<Success, Failure, Forced, Environment> {
    mapProgress { impossible($0) }
  }
}

extension Task where Environment == Any {
  public func settingEnvironmentType<Forced>(to _: Forced.Type) -> Task<Success, Failure, Progress, Forced> {
    mapEnvironment { $0 }
  }
}

// MARK: - Canceling

public struct UniqueCancel: Hashable, Identifiable {
  public let id: AnyHashable
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

private func impossible<A>(_: Never) -> A {
  /// This will never be executed.
}

private func impossible(_: Never) {
  /// This will never be executed.
}
