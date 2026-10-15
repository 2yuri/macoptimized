import Foundation
import Testing
@testable import MacOptimized

/// Opt-in: `MACOPT_BENCH=/path swift test -c release -Xswiftc -enable-testing --filter LensBenchmark`
struct LensBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACOPT_BENCH"] != nil))
    func scanSpeed() async {
        let path = ProcessInfo.processInfo.environment["MACOPT_BENCH"]!
        for run in 1...3 {
            let start = Date()
            let root = await DiskScanner().scan(URL(fileURLWithPath: path))
            let seconds = Date().timeIntervalSince(start)
            var rusage = rusage()
            getrusage(RUSAGE_SELF, &rusage)
            print(String(format: "BENCH run %d: %.2fs  %d files  %@  peak RSS %d MB",
                         run, seconds, root.fileCount, Bytes.format(root.size), Int(rusage.ru_maxrss) / 1_048_576))
        }
    }
}
