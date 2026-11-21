import Foundation

private let containerBundleID = "com.photoviewer.app"

enum InstallHelperError: Error, CustomStringConvertible {
  case requestMissing
  case requestUnreadable
  case pathsRejected

  var description: String {
    switch self {
    case .requestMissing: return "requestMissing"
    case .requestUnreadable: return "requestUnreadable"
    case .pathsRejected: return "pathsRejected"
    }
  }
}

do {
  try runInstallHelper()
} catch {
  log("PhotoViewerInstallHelper: \(error)")
  exit(1)
}

private func runInstallHelper() throws {
  let request = try readInstallRequest()
  // Hand the copy to a detached shell. This process is inside the bundle that
  // is about to be replaced, so it must exit before that bundle is removed.
  let scriptPath = "/tmp/photo-viewer-install.sh"
  guard let scriptFile = fopen(scriptPath, "w") else {
    throw InstallHelperError.requestUnreadable
  }
  fputs("#!/bin/bash\n", scriptFile)
  fputs("set -u\n", scriptFile)
  fputs("if [ \"${PV_DETACHED-}\" != \"1\" ]; then\n", scriptFile)
  fputs("  PV_DETACHED=1 nohup /bin/bash \"$0\" \"$@\" >>/tmp/PhotoViewerInstallHelper.log 2>&1 &\n", scriptFile)
  fputs("  exit 0\n", scriptFile)
  fputs("fi\n", scriptFile)
  fputs("PID=\"$1\"\n", scriptFile)
  fputs("SOURCE=\"$2\"\n", scriptFile)
  fputs("DEST=\"$3\"\n", scriptFile)
  fputs("echo \"waiting for $PID\"\n", scriptFile)
  fputs("while kill -0 \"$PID\" 2>/dev/null; do\n", scriptFile)
  fputs("  sleep 0.1\n", scriptFile)
  fputs("done\n", scriptFile)
  fputs("sleep 0.6\n", scriptFile)
  fputs("echo \"replacing $DEST\"\n", scriptFile)
  fputs("xattr -cr \"$SOURCE\" || true\n", scriptFile)
  fputs("rm -rf \"$DEST\"\n", scriptFile)
  fputs("cp -R \"$SOURCE\" \"$DEST\"\n", scriptFile)
  fputs("xattr -cr \"$DEST\" || true\n", scriptFile)
  fputs("echo \"opening $DEST\"\n", scriptFile)
  fputs("open -n \"$DEST\"\n", scriptFile)
  fputs("echo \"installed $DEST\"\n", scriptFile)
  fclose(scriptFile)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/bash")
  process.arguments = [
    scriptPath,
    "\(request.pid)",
    request.source.path,
    request.destination.path,
  ]
  try process.run()
  process.waitUntilExit()
  log("installer detached for \(request.destination.path)")
}

private struct InstallRequest {
  let source: URL
  let destination: URL
  let pid: Int32
}

private func readInstallRequest() throws -> InstallRequest {
  let fileManager = FileManager.default
  guard let url = requestFileURL(), fileManager.fileExists(atPath: url.path) else {
    throw InstallHelperError.requestMissing
  }
  let text = try String(contentsOf: url, encoding: .utf8)
  let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  guard lines.count >= 3, let pid = Int32(lines[0]) else {
    throw InstallHelperError.requestUnreadable
  }
  let sourcePath = lines[1]
  let destinationPath = lines[2]

  let source = URL(fileURLWithPath: sourcePath, isDirectory: true)
  let destination = URL(fileURLWithPath: destinationPath, isDirectory: true)
  guard isPhotoViewerApp(source), isPhotoViewerApp(destination),
        sourcePath.contains("/photo_viewer/updates/"),
        fileManager.fileExists(atPath: source.path),
        fileManager.fileExists(atPath: destination.path)
  else {
    throw InstallHelperError.pathsRejected
  }
  try? fileManager.removeItem(at: url)
  return InstallRequest(source: source, destination: destination, pid: pid)
}

/// The sandboxed app writes this beside the unpacked update. Command-line
/// arguments from that app are dropped by Launch Services.
private func requestFileURL() -> URL? {
  let home = FileManager.default.homeDirectoryForCurrentUser
  let candidates = [
    home.appendingPathComponent(
      "Library/Containers/\(containerBundleID)/Data/Library/Application Support/photo_viewer/updates/staging/install-request.txt"
    ),
    home.appendingPathComponent(
      "Library/Application Support/photo_viewer/updates/staging/install-request.txt"
    ),
  ]
  return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates.first
}

private func isPhotoViewerApp(_ url: URL) -> Bool {
  url.lastPathComponent == "Photo Viewer.app"
}

private func log(_ message: String) {
  let line = message + "\n"
  fputs(line, stderr)
  if let data = line.data(using: .utf8) {
    let url = URL(fileURLWithPath: "/tmp/PhotoViewerInstallHelper.log")
    if FileManager.default.fileExists(atPath: url.path),
       let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    } else {
      try? data.write(to: url)
    }
  }
}
