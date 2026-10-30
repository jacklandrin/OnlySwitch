/// Only display-brightness auxiliary media keys, never ordinary function or keyboard illumination keys.
public struct BrightnessKeyEvent: Equatable, Sendable {
    public enum Key: Hashable, Sendable { case increase, decrease }
    public let key: Key
    public let isKeyDown: Bool
    public let isRepeat: Bool
    public init(key: Key, isKeyDown: Bool, isRepeat: Bool = false) {
        self.key = key; self.isKeyDown = isKeyDown; self.isRepeat = isRepeat
    }
    public init?(subtype: Int16, data1: Int) {
        guard subtype == 8 else { return nil }
        switch (data1 & 0xFFFF_0000) >> 16 {
        case 2: key = .increase
        case 3: key = .decrease
        default: return nil
        }
        switch (data1 & 0xFF00) >> 8 {
        case 0x0A: isKeyDown = true
        case 0x0B: isKeyDown = false
        default: return nil
        }
        isRepeat = data1 & 1 != 0
    }
}
