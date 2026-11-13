import Foundation

/// The Settings add/edit sheet. `editingID == nil` means a new bookmark.
public struct BrowserBookmarkDraft: Equatable, Sendable {
    public var editingID: UUID?
    public var title: String
    public var address: String
    public var usesMobileUserAgent: Bool
    public var showsInvalidAddress = false

    public init(editingID: UUID? = nil, title: String = "", address: String = "", usesMobileUserAgent: Bool = false) {
        self.editingID = editingID
        self.title = title
        self.address = address
        self.usesMobileUserAgent = usesMobileUserAgent
    }
}
