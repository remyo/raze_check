// Run with the exact boundedDocumentCopy helper extracted from AppDelegate.
// No Flutter/UIKit/provider mocks: this tests Foundation stream bounds only.
let fm = FileManager.default
let dir = fm.temporaryDirectory.appendingPathComponent("raze-stream-test-" + UUID().uuidString)
try fm.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: dir) }
let input = dir.appendingPathComponent("input"), output = dir.appendingPathComponent("output")
try Data(repeating: 42, count: 65537).write(to: input)
for metadata: Int? in [nil, -1, 1, Int.max] {
  do { try boundedDocumentCopy(input, output, 65536, metadata); fatalError("accepted oversized stream") }
  catch is DocumentLimitError { precondition(!fm.fileExists(atPath: output.path)) }
}
try Data(repeating: 42, count: 65536).write(to: input)
try boundedDocumentCopy(input, output, 65536, nil)
let copied = try Data(contentsOf: output)
precondition(copied == Data(repeating: 42, count: 65536))
try fm.removeItem(at: input)
do { try boundedDocumentCopy(input, output, 65536, nil); fatalError("accepted unavailable file") }
catch { precondition(!fm.fileExists(atPath: output.path)) }
print("Swift native streaming: unknown/lying metadata, exact limit, over-limit cleanup, unavailable passed")
