import Extensions

/// Every user-facing browser string key, so the localization test can check the catalog.
public enum BrowserStrings {
    public static let keys = [
        "Browser", "Browser Back", "Browser Forward", "Browser Reload", "Browser Stop", "Browser Home",
        "Browser Address", "Browser Invalid Address", "Browser More", "Browser Open In Default Browser",
        "Browser Mobile Version", "Browser Add Current Page", "Browser Bookmarks", "Browser Add Bookmark",
        "Browser Edit Bookmark", "Browser Delete Bookmark", "Browser Bookmark Title", "Browser Bookmark Title Placeholder",
        "Browser Bookmark Address", "Browser Save", "Browser Cancel", "Browser Empty Title", "Browser Empty Message",
        "Browser Manage Bookmarks", "Browser Settings Empty", "Browser Website Data", "Browser Website Data Note",
        "Browser Clear Website Data", "Browser Clear Website Data Title", "Browser Clear Website Data Message",
        "Browser Clear", "Browser Storage Corrupted", "Browser Load Failed",
    ]

    public static func text(_ key: String) -> String { key.localized() }
}
