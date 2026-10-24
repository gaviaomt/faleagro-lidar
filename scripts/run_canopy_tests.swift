import Foundation

@main
struct CanopyTestMain {
    static func main() {
        let failures = CanopySelfTest.failures()
        if failures.isEmpty {
            print("OK contas do dossel")
            return
        }
        for failure in failures {
            fputs("FAIL \(failure)\n", stderr)
        }
        exit(1)
    }
}
