//
//  RadioSetting.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import ComposableArchitecture
import RadioBrowser
import SwiftUI

struct RadioSettingView: View {

    @StateObject var radioSettingVM = RadioSettingVM()
    let store: StoreOf<RadioStationsFeature>

    var body: some View {
        VStack(spacing: 0) {
            playbackSettings
                .padding(.horizontal, 16)
                .padding(.top, 12)
            RadioStationsView(store: store)
        }
        .background(.background)
    }

    private var playbackSettings: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                effectToggles
                Spacer(minLength: 12)
                volume
            }
            VStack(alignment: .leading, spacing: 10) {
                effectToggles
                volume
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RadioSettingsCard())
    }

    private var effectToggles: some View {
        HStack(spacing: 16) {
            Toggle("Sound Wave Effect".localized(), isOn: $radioSettingVM.soundWaveEffectDisplay)
            HStack(spacing: 10) {
                Text("Allow Notification:".localized())
                    .foregroundStyle(.secondary)
                Toggle("Changing Station".localized(), isOn: $radioSettingVM.allowNotificationChangingStation)
                Toggle("Soundtrack".localized(), isOn: $radioSettingVM.allowNotificationTrack)
            }
        }
        .toggleStyle(.checkbox)
        .fixedSize()
    }

    private var volume: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: $radioSettingVM.sliderValue)
                .frame(minWidth: 120, maxWidth: 180)
                .accessibilityLabel("Volume".localized())
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .help("Volume".localized())
    }
}

/// Liquid Glass on macOS 26, material with a hairline elsewhere.
private struct RadioSettingsCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)) }
        }
    }
}

#if DEBUG
struct RadioSetting_Previews: PreviewProvider {
    static var previews: some View {
        RadioSettingView(store: Store(initialState: RadioStationsFeature.State()) {
            RadioStationsFeature()
        } withDependencies: {
            $0.radioLibraryClient = .previewValue
        })
        .frame(width: 700, height: 520)
    }
}
#endif
