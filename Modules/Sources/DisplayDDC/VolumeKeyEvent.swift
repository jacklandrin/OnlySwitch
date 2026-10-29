/// A volume media key from an `NSEvent.EventType.systemDefined` event. `subtype` 8 is
/// NX_SUBTYPE_AUX_CONTROL_BUTTONS; `data1` packs key code, key state and the repeat flag.
public struct VolumeKeyEvent: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case volumeUp
        case volumeDown
        case mute
    }

    public let key: Key
    public let isKeyDown: Bool
    public let isRepeat: Bool

    public init(key: Key, isKeyDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isKeyDown = isKeyDown
        self.isRepeat = isRepeat
    }

    public init?(subtype: Int16, data1: Int) {
        guard subtype == 8 else { return nil }
        switch (data1 & 0xFFFF_0000) >> 16 {
        case 0: key = .volumeUp     // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown   // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute         // NX_KEYTYPE_MUTE
        default: return nil
        }
        switch (data1 & 0xFF00) >> 8 {
        case 0x0A: isKeyDown = true
        case 0x0B: isKeyDown = false
        default: return nil
        }
        isRepeat = data1 & 0x1 != 0
    }
}
