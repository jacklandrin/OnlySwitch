//
//  KeyLightFeature.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/4/28.
//

import ComposableArchitecture
import Foundation

struct KeyLightFeature: Reducer {
    struct State: Equatable {
        var brightness = 0.0
        var autoBrightness = false
    }

    enum Action: Equatable {
        case viewAppeared
        case setBrightness(Double)
        case setAutoBrightness(Bool)
    }

    @Dependency(\.keyLightService) var keyLightService

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .viewAppeared:
                    keyLightService.loadKeyboardManager()
                    let brightness = keyLightService.brightness()
                    state.brightness = brightness < 0.1 ? 0.1 : brightness
                    state.autoBrightness = keyLightService.autoBrightness()
                    return .none

                case let .setBrightness(brightness):
                    state.brightness = brightness < 0.1 ? 0.1 : brightness
                    keyLightService.setBrightness(brightness)
                    return .none

                case let .setAutoBrightness(isAuto):
                    state.autoBrightness = isAuto
                    keyLightService.setAutoBrightness(isAuto)
                    return .none
            }
        }
    }
}
