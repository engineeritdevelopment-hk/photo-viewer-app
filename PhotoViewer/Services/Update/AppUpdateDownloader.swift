import Foundation

enum AppUpdateDownloadError: LocalizedError {
  case failed

  var errorDescription: String? {
    "The update download could not be completed."
  }
}

final class AppUpdateDownloader: NSObject, @unchecked Sendable {
  private var continuation: CheckedContinuation<URL, Error>?
  private var onProgress: (@MainActor (Double) -> Void)?
  private var session: URLSession?
  private var destinationURL: URL?

  func download(
    from remoteURL: URL,
    into directory: URL,
    onProgress: @escaping @MainActor (Double) -> Void
  ) async throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let filename = remoteURL.lastPathComponent.isEmpty ? "update.zip" : remoteURL.lastPathComponent
    let destination = directory.appendingPathComponent(filename, isDirectory: false)
    if FileManager.default.fileExists(atPath: destination.path) {
      try? FileManager.default.removeItem(at: destination)
    }
    destinationURL = destination
    self.onProgress = onProgress

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let configuration = URLSessionConfiguration.ephemeral
      let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      self.session = session
      let task = session.downloadTask(with: remoteURL)
      task.resume()
    }
  }
}

extension AppUpdateDownloader: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    defer {
      session.invalidateAndCancel()
      self.session = nil
    }
    guard let destinationURL else {
      continuation?.resume(throwing: AppUpdateDownloadError.failed)
      continuation = nil
      return
    }
    do {
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.moveItem(at: location, to: destinationURL)
      continuation?.resume(returning: destinationURL)
    } catch {
      continuation?.resume(throwing: error)
    }
    continuation = nil
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    continuation?.resume(throwing: error)
    continuation = nil
    session.invalidateAndCancel()
    self.session = nil
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0, let onProgress else { return }
    let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    Task { @MainActor in onProgress(min(1, max(0, fraction))) }
  }
}