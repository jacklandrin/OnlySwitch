/// Converts pet state into the six host attributes of the skin contract. Values come only from
/// enums and booleans, never from user or model text, so the generated script cannot be injected.
enum DesktopPetSkinAttributes {
    /// Only `values(for:reduceMotion:isPaused:)` can create one, so `script(_:)` never sees free text.
    struct Attribute: Equatable {
        let name: String
        let value: String

        fileprivate init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    static func values(for state: DesktopPetAnimationState, reduceMotion: Bool, isPaused: Bool) -> [Attribute] {
        let pomodoro = switch state.pomodoroPhase {
        case .focus: "focus"
        case .breakTime: "break"
        case nil: "none"
        }
        return [
            Attribute("data-state", state.animation.rawValue),
            Attribute("data-control", state.isControlPresented ? "on" : "off"),
            Attribute("data-pomodoro", pomodoro),
            Attribute("data-hungry", String(state.isHungry)),
            Attribute("data-reduce-motion", String(reduceMotion)),
            Attribute("data-paused", String(isPaused)),
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
