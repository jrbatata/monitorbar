import Foundation
import Darwin

let path = CommandLine.arguments[1]
let lib = dlopen("/System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework/CarbonCore", RTLD_LAZY)!
typealias Handle = UnsafeMutablePointer<UnsafeMutableRawPointer?>
let makeRef = unsafeBitCast(dlsym(lib, "FSPathMakeRef")!, to: (@convention(c) (UnsafePointer<CChar>, UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>?) -> Int32).self)
let makeAlias = unsafeBitCast(dlsym(lib, "FSNewAlias")!, to: (@convention(c) (UnsafeRawPointer?, UnsafeRawPointer, UnsafeMutablePointer<Handle?>) -> Int16).self)
let aliasSize = unsafeBitCast(dlsym(lib, "GetAliasSize")!, to: (@convention(c) (Handle) -> Int32).self)
let target = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8)
defer { target.deallocate() }
let refStatus = path.withCString { makeRef($0, target, nil) }
guard refStatus == 0 else { print("FSRef error: \(refStatus)"); exit(1) }
var handle: Handle?
let status = makeAlias(nil, target, &handle)
guard status == 0, let handle, let pointer = handle.pointee else { print("Alias error: \(status)"); exit(1) }
let alias = Data(bytes: pointer, count: Int(aliasSize(handle)))
try alias.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
let bookmark = CFURLCreateBookmarkDataFromAliasRecord(nil, alias as CFData)!.takeRetainedValue() as Data
var stale = false
let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
print("Native reference resolves: \(url.path), stale: \(stale), bytes: \(alias.count)")
