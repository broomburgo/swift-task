import Foundation
import SwiftTask

// MARK: - DispatchQueue

extension Task {
  public func receive(on queue: DispatchQueue) -> Task {
    Task { env, yield in
      self(environment: env) { step in
        queue.async {
          yield(step)
        }
      }
    }
  }
}

// MARK: - HTTP Request

public struct HTTPResponse {
  public let response: HTTPURLResponse
  public let data: Data
}

public enum HTTPError: Error {
  case requestFailed(Error)
  case noHTTPURLResponse
  case noData
}

extension Task where
  Success == CancelableValue<HTTPResponse>,
  Failure == HTTPError,
  Progress == CancelableOngoing<Double>,
  Environment == URLSession {
  public static func httpRequest(_ request: URLRequest) -> Task {
    Task { session, yield in
      var progressObservation: NSKeyValueObservation?
      let dataTask = session.dataTask(with: request) {
        progressObservation?.invalidate()
        yield(.completed(Result(data: $0, response: $1, error: $2)))
      }

      if #available(macOS 10.13, *) {
        progressObservation = dataTask.observe(\.progress) { dataTask, _ in
          yield(.ongoing(.next(dataTask.progress.fractionCompleted)))
        }
      }

      dataTask.resume()
      yield(.ongoing(.start(UniqueCancel(id: dataTask.taskIdentifier, run: dataTask.cancel))))
    }
  }
}

// MARK: - Private

extension Result where
  Success == CancelableValue<HTTPResponse>,
  Failure == HTTPError {
  fileprivate init(data: Data?, response: URLResponse?, error: Error?) {
    if let error = error {
      self = (error as NSError).code == NSURLErrorCancelled
        ? .success(.canceled)
        : .failure(.requestFailed(error))
      return
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      self = .failure(.noHTTPURLResponse)
      return
    }

    guard let data = data else {
      self = .failure(.noData)
      return
    }

    self = .success(.done(HTTPResponse(response: httpResponse, data: data)))
  }
}
