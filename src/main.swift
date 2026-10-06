// dbx-materialize — force Dropbox "online-only" placeholders to download locally.
//
// Dropbox online-only files (legacy Smart Sync) are 0-byte stubs carrying a
// `com.dropbox.placeholder` xattr. A raw read()/cat/cp returns 0 bytes and does
// NOT trigger a download. What does trigger it is an NSFileCoordinator
// *coordinated read* (what apps do when they open a file). This tool performs
// that read and blocks until the file is fully local.
//
// The same detection also covers macOS File Provider "dataless" files (iCloud
// Drive, File-Provider Dropbox), so it works for those too.
import Darwin
import Foundation

let version = "1.0.0"

let usage = """
usage: dbx-materialize [options] <path>...

Download Dropbox online-only (placeholder) files so they are stored locally.
Paths can be files or directories (recursed), absolute or relative.

options:
  -s, --status        report online-only vs local; download nothing
  -j, --jobs N        parallel downloads (default 4)
  -f, --min-free GB   skip files once free disk would drop below GB (default 5)
  -q, --quiet         only print failures and the summary
  -h, --help          show this help
  -V, --version       show version

output (one line per file):
  OK      downloaded now          LOCAL   already local (nothing to do)
  ONLINE  online-only (--status)  FLOOR   skipped: not enough free disk
  FAIL    error (exit code 1)

exit codes: 0 all good, 1 some file failed/skipped for disk, 2 bad usage
"""

func die(_ msg: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

// MARK: - Args

var statusOnly = false
var jobs = 4
var minFreeGB = 5.0
var quiet = false
var inputs: [String] = []

var argv = CommandLine.arguments.dropFirst().makeIterator()
var endOfOptions = false
while let a = argv.next() {
    if endOfOptions || !a.hasPrefix("-") || a == "-" { inputs.append(a); continue }
    switch a {
    case "--": endOfOptions = true
    case "-s", "--status", "--check": statusOnly = true
    case "-q", "--quiet": quiet = true
    case "-h", "--help": print(usage); exit(0)
    case "-V", "--version": print("dbx-materialize \(version)"); exit(0)
    case "-j", "--jobs":
        guard let v = argv.next(), let n = Int(v), n > 0 else { die("--jobs needs a positive integer") }
        jobs = n
    case "-f", "--min-free":
        guard let v = argv.next(), let n = Double(v), n >= 0 else { die("--min-free needs a number of GB") }
        minFreeGB = n
    default: die("unknown option: \(a)\n\n\(usage)")
    }
}
if inputs.isEmpty { die(usage) }

// MARK: - File state

struct FileState {
    let size: Int64
    let onlineOnly: Bool
}

let SF_DATALESS_FLAG: UInt32 = 0x4000_0000  // sys/stat.h SF_DATALESS

func fileState(_ path: String) -> FileState? {
    var st = stat()
    guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
    let size = Int64(st.st_size)
    let hasDropboxXattr = getxattr(path, "com.dropbox.placeholder", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    let dataless = (st.st_flags & SF_DATALESS_FLAG) != 0
    let noBlocks = size > 0 && st.st_blocks == 0
    return FileState(size: size, onlineOnly: hasDropboxXattr || dataless || noBlocks)
}

func freeBytes() -> Int64 {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return v?.volumeAvailableCapacityForImportantUsage ?? Int64.max
}

func human(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

// MARK: - Collect files

let cwd = FileManager.default.currentDirectoryPath
var files: [String] = []
var hadMissing = false
for raw in inputs {
    let expanded = (raw as NSString).expandingTildeInPath
    let abs = expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
    let path = (abs as NSString).standardizingPath
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
        FileHandle.standardError.write("FAIL    \(path): no such file or directory\n".data(using: .utf8)!)
        hadMissing = true
        continue
    }
    if !isDir.boolValue { files.append(path); continue }
    let en = FileManager.default.enumerator(
        at: URL(fileURLWithPath: path),
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsPackageDescendants])
    while let u = en?.nextObject() as? URL {
        if u.lastPathComponent == ".DS_Store" || u.lastPathComponent.hasPrefix(".dropbox") { continue }
        if (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            files.append(u.path)
        }
    }
}

// MARK: - Work

let lock = NSLock()
var nOK = 0, nLocal = 0, nOnline = 0, nFloor = 0, nFail = 0
var bytesDownloaded: Int64 = 0, bytesOnline: Int64 = 0
let floorBytes = Int64(minFreeGB * 1_073_741_824)
// NB: legacy Smart Sync placeholders report st_size 0, so the floor check is
// effectively "free space right now >= floor" before each file starts — a single
// huge file can still dip below it. File Provider placeholders do report size.
var reservedBytes: Int64 = 0  // in-flight downloads, so parallel jobs don't overshoot the floor

func report(_ tag: String, _ path: String, _ extra: String = "", always: Bool = false) {
    guard always || !quiet else { return }
    let line = "\(tag.padding(toLength: 7, withPad: " ", startingAt: 0)) \(path)\(extra.isEmpty ? "" : "  (\(extra))")\n"
    if tag == "FAIL" { FileHandle.standardError.write(line.data(using: .utf8)!) }
    else { FileHandle.standardOutput.write(line.data(using: .utf8)!) }
}

func materialize(_ path: String) -> String? {
    var coordErr: NSError?
    var readErr: String?
    NSFileCoordinator().coordinate(readingItemAt: URL(fileURLWithPath: path),
                                   options: [.forUploading], error: &coordErr) { u in
        do {
            let fh = try FileHandle(forReadingFrom: u)
            _ = try fh.read(upToCount: 1)
            try fh.close()
        } catch { readErr = error.localizedDescription }
    }
    if let e = coordErr { return "coordination error: \(e.localizedDescription)" }
    return readErr
}

func process(_ path: String) {
    guard let st = fileState(path) else {
        lock.lock(); nFail += 1; lock.unlock()
        report("FAIL", path, "not a regular file", always: true); return
    }
    if !st.onlineOnly {
        lock.lock(); nLocal += 1; lock.unlock()
        report("LOCAL", path, human(st.size)); return
    }
    if statusOnly {
        lock.lock(); nOnline += 1; bytesOnline += st.size; lock.unlock()
        report("ONLINE", path, st.size > 0 ? human(st.size) : "size unknown until downloaded"); return
    }
    lock.lock()
    let ok = freeBytes() - reservedBytes - st.size >= floorBytes
    if ok { reservedBytes += st.size } else { nFloor += 1 }
    lock.unlock()
    guard ok else { report("FLOOR", path, "free disk below \(minFreeGB) GB floor", always: true); return }

    let err = materialize(path)
    let after = fileState(path)
    lock.lock()
    reservedBytes -= st.size
    if err == nil, let a = after, !a.onlineOnly {
        nOK += 1; bytesDownloaded += a.size
        lock.unlock()
        report("OK", path, human(a.size))
    } else {
        nFail += 1
        lock.unlock()
        report("FAIL", path, err ?? "still online-only after coordinated read", always: true)
    }
}

let queue = OperationQueue()
queue.maxConcurrentOperationCount = jobs
for f in files { queue.addOperation { process(f) } }
queue.waitUntilAllOperationsAreFinished()

// MARK: - Summary

var parts: [String] = []
if statusOnly {
    parts.append("\(nOnline) online-only" + (bytesOnline > 0 ? " (\(human(bytesOnline)))" : ""))
} else {
    parts.append("\(nOK) downloaded (\(human(bytesDownloaded)))")
}
parts.append("\(nLocal) already local")
if nFloor > 0 { parts.append("\(nFloor) skipped for disk floor \(minFreeGB) GB") }
if nFail > 0 || hadMissing { parts.append("\(nFail + (hadMissing ? 1 : 0)) failed") }
FileHandle.standardError.write("dbx-materialize: \(parts.joined(separator: ", ")); \(human(freeBytes())) free\n".data(using: .utf8)!)
exit(nFail > 0 || nFloor > 0 || hadMissing ? 1 : 0)
