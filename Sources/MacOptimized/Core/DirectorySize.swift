import Darwin
import Foundation

enum DirectorySize {
    /// On-disk size of a file or a whole directory tree. Unreadable items count as 0.
    /// Symlinks and cloud-only placeholders are not followed.
    static func allocated(of url: URL) -> Int64 {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return 0 }
        switch st.st_mode & S_IFMT {
        case S_IFDIR:
            let scanner = FastScanner()
            scanner.walk(url.path) { path, entries in
                entries.filter { $0.kind == .directory }.map { FastScanner.join(path, $0.name) }
            }
            return scanner.scannedBytes
        case S_IFREG:
            return st.st_flags & UInt32(SF_DATALESS) != 0 ? 0 : Int64(st.st_blocks) * 512
        default:
            return 0
        }
    }
}
