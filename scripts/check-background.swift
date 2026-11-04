import Foundation
import CoreServices

// Validate resolution, not just AliasRecord syntax. Input is a mounted DMG root.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let metadata = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : root.appendingPathComponent(".DS_Store").path))
func number(_ offset: Int) -> Int { metadata[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) } }
let allocator = number(8) + 4
let superblock = (number(allocator + 12) & ~31) + 4
let node = number(superblock)
var cursor = (number(allocator + 8 + node * 4) & ~31) + 4
precondition(number(cursor) == 0)
let count = number(cursor + 4); cursor += 8
var background: Data?
for _ in 0..<count {
    let nameLength = number(cursor); cursor += 4
    let name = String(data: metadata[cursor..<(cursor + nameLength * 2)], encoding: .utf16BigEndian)!
    cursor += nameLength * 2
    let key = String(data: metadata[cursor..<(cursor + 4)], encoding: .ascii)!
    let type = String(data: metadata[(cursor + 4)..<(cursor + 8)], encoding: .ascii)!
    cursor += 8
    if type == "blob" {
        let length = number(cursor); cursor += 4
        let blob = metadata[cursor..<(cursor + length)]; cursor += length
        if name == ".", key == "icvp" {
            let plist = try PropertyListSerialization.propertyList(from: blob, format: nil) as! [String: Any]
            background = plist["backgroundImageAlias"] as? Data
        }
    } else { cursor += 4 }
}
let alias = background!
let bookmark = CFURLCreateBookmarkDataFromAliasRecord(nil, alias as CFData)!.takeRetainedValue() as Data
var stale = false
do {
    let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: root, bookmarkDataIsStale: &stale)
    print("Background resolves to: \(resolved.path); exists: \(FileManager.default.fileExists(atPath: resolved.path)); stale: \(stale)")
    precondition(resolved.standardizedFileURL == root.appendingPathComponent(".background.tiff").standardizedFileURL)
} catch {
    print("Background resolution FAILED: \(error)")
    exit(1)
}
