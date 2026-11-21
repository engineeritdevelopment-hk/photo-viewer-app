import AppKit
import Foundation

enum AppUpdateInstallError: LocalizedError {
  case helperMissing
  case extractFailed
  case appBundleNotFound
  case helperLaunchFailed(String)

  var errorDescription: String? {
    switch self {
    case .helperMissing:
      return "This build does not include the install helper."
    case .extractFailed:
      return "The downloaded update could not be unpacked."
    case .appBundleNotFound:
      return "The update archive did not contain Photo Viewer.app."
    case .helperLaunchFailed(let detail):
      return "Could not apply the update (\(detail))."
    }
  }
}

enum AppUpdateInstaller {
  static func install(zipURL: URL) async throws {
    let fileManager = FileManager.default
    let workRoot = ApplicationPaths.updateStaging
    if fileManager.fileExists(atPath: workRoot.path) {
      try? fileManager.removeItem(at: workRoot)
    }
    try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)

    let extractRoot = workRoot.appendingPathComponent("extracted", isDirectory: true)
    try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)
    try unzipArchive(at: zipURL, to: extractRoot)

    guard let appBundle = findApplicationBundle(in: extractRoot) else {
      throw AppUpdateInstallError.appBundleNotFound
    }

    guard let bundledHelper = installHelperURL() else {
      throw AppUpdateInstallError.helperMissing
    }

    // Launch the helper that is already inside this app. A copy stored in the
    // sandbox container is rejected by Launch Services. Arguments are dropped
    // too, so the paths are written to a file the helper knows how to find.
    try writeInstallRequest(
      source: appBundle,
      destination: Bundle.main.bundleURL,
      parentPID: ProcessInfo.processInfo.processIdentifier,
      at: workRoot.appendingPathComponent("install-request.txt")
    )

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.createsNewApplicationInstance = true

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      NSWorkspace.shared.openApplication(at: bundledHelper, configuration: configuration) { _, error in
        if let error {
          continuation.resume(throwing: AppUpdateInstallError.helperLaunchFailed(error.localizedDescription))
        } else {
          continuation.resume()
        }
      }
    }

    // The helper waits for this process to exit, then replaces the bundle.
    // terminate() can stall while this sheet is open, so leave immediately.
    exit(0)
  }

  private static func writeInstallRequest(source: URL, destination: URL, parentPID: Int32, at url: URL) throws {
    let text = "\(parentPID)\n\(source.path)\n\(destination.path)\n"
    try Data(text.utf8).write(to: url, options: .atomic)
  }

  private static func unzipArchive(at zipURL: URL, to destination: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-xk", zipURL.path, destination.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw AppUpdateInstallError.extractFailed
    }
  }

  private static func installHelperURL() -> URL? {
    let bundle = Bundle.main
    let candidates = [
      bundle.bundleURL.appendingPathComponent("Contents/Resources/PhotoViewerInstallHelper.app"),
      bundle.bundleURL.appendingPathComponent("Contents/Library/LoginItems/PhotoViewerInstallHelper.app"),
      bundle.bundleURL.appendingPathComponent("Contents/Helpers/PhotoViewerInstallHelper.app"),
      bundle.bundleURL.appendingPathComponent("Contents/MacOS/PhotoViewerInstallHelper.app"),
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
  }

  private static func findApplicationBundle(in root: URL) -> URL? {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return nil }

    for case let url as URL in enumerator {
      guard url.pathExtension == "app" else { continue }
      let name = url.deletingPathExtension().lastPathComponent
      if name == "Photo Viewer" { return url }
    }
    return nil
  }
}