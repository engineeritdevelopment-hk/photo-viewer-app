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
  static func install(zipURL: URL) throws {
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

    guard let helper = installHelperURL() else {
      throw AppUpdateInstallError.helperMissing
    }

    let process = Process()
    process.executableURL = helper
    process.arguments = [
      "--install", appBundle.path,
      "--to", Bundle.main.bundleURL.path,
      "--wait-for", "\(ProcessInfo.processInfo.processIdentifier)",
    ]

    do {
      try process.run()
    } catch {
      throw AppUpdateInstallError.helperLaunchFailed(error.localizedDescription)
    }

    Task { @MainActor in
      NSApp.terminate(nil)
    }
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
    if let auxiliary = bundle.url(forAuxiliaryExecutable: "PhotoViewerInstallHelper") {
      return auxiliary
    }
    if let inResources = bundle.url(forResource: "PhotoViewerInstallHelper", withExtension: nil) {
      return inResources
    }
    let candidate = bundle.bundleURL
      .appendingPathComponent("Contents/MacOS/PhotoViewerInstallHelper")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate
    }
    return nil
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