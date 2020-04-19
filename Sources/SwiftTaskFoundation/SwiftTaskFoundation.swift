import Foundation
import SwiftTask

// MARK: - DispatchQueue

extension Task {
  public func receive(on queue: DispatchQueue) -> Task {
    Task { environment, yield in
      self.run(environment) { step in
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
  Success == HTTPResponse,
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

      progressObservation = dataTask.observe(\.progress) { dataTask, _ in
        yield(.ongoing(.next(dataTask.progress.fractionCompleted)))
      }

      dataTask.resume()
      yield(.ongoing(.start(UniqueCancel(id: dataTask.taskIdentifier, run: dataTask.cancel))))
    }
  }
}

// MARK: - Private

extension Result where Success == HTTPResponse, Failure == HTTPError {
  fileprivate init(data: Data?, response: URLResponse?, error: Error?) {
    if let error = error {
      self = .failure(.requestFailed(error))
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

    self = .success(.init(response: httpResponse, data: data))
  }
}
