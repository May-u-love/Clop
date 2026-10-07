import Foundation

public enum WarpDropError: Error {
    case unavailable
}

public struct WarpDropClient {
    public init() {}
    @discardableResult
    public func send(files: [URL], multi: Bool = false, maxReceivers: Int = 0,
                     onRoomCreated: @escaping (String) -> Void = { _ in },
                     onDownloadCompleted: @escaping (Int) -> Void = { _ in }) async throws -> String {
        throw WarpDropError.unavailable
    }
}
