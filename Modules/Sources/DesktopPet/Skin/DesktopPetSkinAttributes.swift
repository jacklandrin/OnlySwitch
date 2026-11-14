/// Converts pet state into the six host attributes of the skin contract. Values come only from
/// enums and booleans, never from user or model text, so the generated script cannot be injected.
enum DesktopPetSkinAttributes {
    typealias Attribute = (name: String, value: String)

    static func values(for state: DesktopPetAnimationState, reduceMotion: Bool, isPaused: Bool) -> [Attribute] {
        let pomodoro = switch state.pomodoroPhase {
        case .focus: "focus"
        case .breakTime: "break"
        case nil: "none"
        }
        return [
            ("data-state", state.animation.rawValue),
            ("data-control", state.isControlPresented ? "on" : "off"),
            ("data-pomodoro", pomodoro),
            ("data-hungry", String(state.isHungry)),
            ("data-reduce-motion", String(reduceMotion)),
            ("data-paused", String(isPaused)),
        ]
    }

    static func script(_ attributes: [Attribute]) -> String {
        attributes
            .map { "document.documentElement.setAttribute(\"\($0.name)\",\"\($0.value)\");" }
            .joined()
    }
}

extension DesktopPetAnimationState {
    /// A representative state that resolves to `animation`, used by the Settings preview.
    public static func preview(_ animation: DesktopPetAnimation) -> Self {
        switch animation {
        case .idle: Self()
        case .focus: Self(pomodoroPhase: .focus)
        case .breakTime: Self(pomodoroPhase: .breakTime)
        case .music: Self(isMusicPlaying: true)
        case .working: Self(isAgentWorking: true)
        case .hungry: Self(isHungry: true)
        case .eating: Self(reaction: .eating)
        case .petted: Self(reaction: .petted)
        case .dragging: Self(isDragging: true)
        }
    }
}
