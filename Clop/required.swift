import Foundation

// Community-build stubs replacing the private required.swift (licence internals).
// This build runs as the free version; Pro features stay locked.

let proactive = false

func validReq() -> Bool { true }

@discardableResult func invalidReq(_ products: [Any]?, _ ctx: Any?) -> Bool { false }
@discardableResult func invalidReq2(_ products: [Any]?, _ ctx: Any?) -> Bool { false }
@discardableResult func invalidReq3(_ products: [Any]?, _ ctx: Any?) -> Bool { false }

func hasShortcutsDB() -> Bool { false }
