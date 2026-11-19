import AppKit
import Foundation

enum InstallHelperError: Error {
  case invalidArguments
  case pathsMissing
}

do {
  try runInstallHelper()
} catch {
  fputs("PhotoViewerInstallHelper: \(error)\n", stderr)
  exit(1)
}

private func runInstallHelper() throws {
  let arguments = CommandLine.arguments
  guard
    let installIndex = arguments.firstIndex(of: "--install"),
    installIndex + 1 < arguments.count,
    let targetIndex = arguments.firstIndex(of: "--to"),
    targetIndex + 1 < arguments.count,
    let waitIndex = arguments.firstIndex(of: "--wait-for"),
    waitIndex + 1 < arguments.count,
    let parentPID = Int32(arguments[waitIndex + 1])
  else {
    throw InstallHelperError.invalidArguments
  }

  let sourceApp = URL(fileURLWithPath: arguments[installIndex + 1], isDirectory: true)
  let targetApp = URL(fileURLWithPath: arguments[targetIndex + 1], isDirectory: true)

  guard FileManager.default.fileExists(atPath: sourceApp.path),
    FileManager.default.fileExists(atPath: targetApp.path)
  else {
    throw InstallHelperError.pathsMissing
  }

  waitForProcess(pid: parentPID)
  try stripQuarantine(at: sourceApp)
  try replaceApplication(newApp: sourceApp, destination: targetApp)
  try launchApplication(at: targetApp)
}

private func waitForProcess(pid: Int32) {
  var attempts = 0
  while kill(pid, 0) == 0, attempts < 600 {
    usleep(100_000)
    attempts += 1
  }
  usleep(400_000)
}

private func stripQuarantine(at appURL: URL) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
  process.arguments = ["-cr", appURL.path]
  try process.run()
  process.waitUntilExit()
}

private func replaceApplication(newApp: URL, destination: URL) throws {
  let fileManager = FileManager.default
  if fileManager.fileExists(atPath: destination.path) {
    try fileManager.removeItem(at: destination)
  }
  try fileManager.copyItem(at: newApp, to: destination)
}

private func launchApplication(at appURL: URL) throws {
  let config = NSWorkspace.OpenConfiguration()
  config.activates = true
  let group = DispatchGroup()
  var launchError: Error?
  group.enter()
  NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
    launchError = error
    group.leave()
  }
  group.wait()
  if let launchError { throw launchError }
}