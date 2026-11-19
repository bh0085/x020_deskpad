import Foundation

// Private window-server (SkyLight) calls: read which desktop is where, and move DeskPad's own window to a desktop.
// macOS has no public API for either. A process may move only its own windows this way.
typealias ConnFn = @convention(c) () -> Int32
typealias DisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>
typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
typealias MoveToSpaceFn = @convention(c) (Int32, CFArray, UInt64) -> Void
typealias WindowsSpacesFn = @convention(c) (Int32, CFArray, CFArray) -> Void

enum SkyLight {
    static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    static func sym<T>(_ name: String, _ t: T.Type) -> T? {
        guard let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: t)
    }
    static let conn = sym("SLSMainConnectionID", ConnFn.self)!()
    static let copyDisplaySpaces = sym("SLSCopyManagedDisplaySpaces", DisplaySpacesFn.self)!
    static let copySpacesForWindows = sym("SLSCopySpacesForWindows", SpacesForWindowsFn.self)!
    static let moveToSpace = sym("SLSMoveWindowsToManagedSpace", MoveToSpaceFn.self)
    static let addToSpaces = sym("SLSAddWindowsToSpaces", WindowsSpacesFn.self)
    static let removeFromSpaces = sym("SLSRemoveWindowsFromSpaces", WindowsSpacesFn.self)

    static func displaySpaces() -> [[String: Any]] { (copyDisplaySpaces(conn).takeRetainedValue() as? [[String: Any]]) ?? [] }

    static func spaceID(forUUID uuid: String) -> UInt64? {
        for d in displaySpaces() {
            for s in (d["Spaces"] as? [[String: Any]]) ?? [] where (s["uuid"] as? String) == uuid {
                return (s["ManagedSpaceID"] as? NSNumber)?.uint64Value
            }
        }
        return nil
    }

    static func spaces(ofWindow wid: Int) -> [UInt64] {
        (copySpacesForWindows(conn, 7, [wid] as CFArray)?.takeRetainedValue() as? [NSNumber])?.map { $0.uint64Value } ?? []
    }

    // Put our window on exactly one desktop; true once the window server reports it there and only there.
    static func pin(window wid: Int, to space: UInt64) -> Bool {
        if spaces(ofWindow: wid) == [space] { return true }
        if let moveToSpace { moveToSpace(conn, [wid] as CFArray, space) }
        if spaces(ofWindow: wid) == [space] { return true }
        if let addToSpaces, let removeFromSpaces {
            let others = spaces(ofWindow: wid).filter { $0 != space }
            addToSpaces(conn, [wid] as CFArray, [space] as CFArray)
            if !others.isEmpty { removeFromSpaces(conn, [wid] as CFArray, others as CFArray) }
        }
        return spaces(ofWindow: wid) == [space]
    }
}
