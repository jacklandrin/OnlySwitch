//
//  SoundMixerSettingView.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/07/13.
//

import SwiftUI

// MARK: - Settings page

/// Settings page for the mixer: the menu bar switch plus a live preview of the panel that the
/// menu bar item shows.
struct SoundMixerSettingView: View {

    /// Deliberately not the mixer view model: this page only flips a preference. Keeping the polling
    /// view model — and the panel's `GeometryReader` sliders — out of the settings window keeps a
    /// layout problem here from taking the whole split view down with it.
    @State private var isEnabled = Preferences.shared.soundMixerMenubarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isEnabled) {
                Text("Show sound mixer in the menu bar".localized())
            }
            .toggleStyle(.switch)
            .onChange(of: isEnabled) { _, newValue in
                Preferences.shared.soundMixerMenubarItem = newValue
            }

            Text("Adds its own menu bar icon that opens the panel below — volume for the whole system and for each app that is playing.".localized())
                .font(.caption)
                .foregroundColor(.secondary)

            if isEnabled {
                menubarHint
            }

            Spacer()
        }
        .padding()
    }

    /// Shown once the item exists, because the icon appearing in the menu bar is easy to miss —
    /// and because replacing the system sound item needs a manual step in System Settings.
    /// Kept to the same plain layout as the other setting pages: no `maxWidth: .infinity` inside the
    /// split view's detail column, which produced an unusable width and blanked the whole window.
    private var menubarHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("This icon is now in your menu bar.".localized(),
                  systemImage: "speaker.wave.2.fill")

            Text("To let it replace the system sound icon, turn that one off in System Settings › Control Center › Sound.".localized())
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Open Control Center Settings".localized()) {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
                else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.top, 4)
    }
}

// MARK: - Popover

/// What the menu bar item shows. Owns the view model so the panel keeps polling only while open.
struct SoundMixerPopoverView: View {

    @StateObject private var vm = SoundMixerSettingVM()

    var body: some View {
        SoundMixerPanel(vm: vm)
            .padding(.vertical, 12)
            .frame(width: 320)
    }
}

// MARK: - Panel

/// The mixer itself, laid out like the system sound panel: one prominent output slider, a section
/// per playing app, and the current output device underneath.
struct SoundMixerPanel: View {

    @ObservedObject var vm: SoundMixerSettingVM

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound".localized())
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)

            MixerSlider(value: $vm.systemVolume,
                        height: 22,
                        leadingSymbol: "speaker.fill",
                        trailingSymbol: "speaker.wave.3.fill") { editing in
                editing ? vm.beginInteractive() : commitSystem()
            }
            .onChange(of: vm.systemVolume) { _, _ in
                vm.applySystemVolumeWhileDragging()
            }
            .padding(.horizontal, 14)

            if !vm.rows.isEmpty {
                sectionHeader("Apps".localized())
                VStack(spacing: 10) {
                    ForEach($vm.rows) { $row in
                        appRow($row)
                    }
                }
                .padding(.horizontal, 14)
            }

            if let device = vm.outputDevice {
                sectionHeader("Output".localized())
                outputRow(device)
            }

            Divider()
                .padding(.top, 2)

            Button {
                vm.openSoundSettings()
            } label: {
                Text("Sound Settings…".localized())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
        }
        .onAppear { vm.startAutoRefresh() }
        .onDisappear { vm.stopAutoRefresh() }
    }

    // MARK: Rows

    private func appRow(_ row: Binding<SoundMixerSettingVM.AppRow>) -> some View {
        HStack(spacing: 10) {
            appIcon(row.wrappedValue.icon)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.wrappedValue.name)
                    .font(.system(size: 11))
                    .lineLimit(1)

                MixerSlider(value: row.volume,
                            height: 12,
                            leadingSymbol: nil,
                            trailingSymbol: nil) { editing in
                    editing ? vm.beginInteractive() : commitRow(row.wrappedValue.id)
                }
                .onChange(of: row.wrappedValue.volume) { _, _ in
                    vm.applyVolumeWhileDragging(for: row.wrappedValue.id)
                }
            }

            Button {
                vm.toggleMute(for: row.wrappedValue.id)
            } label: {
                Image(systemName: row.wrappedValue.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundColor(row.wrappedValue.isMuted ? .secondary : .primary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func outputRow(_ device: SoundMixerService.OutputDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbolName)
                .font(.system(size: 11))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(device.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func appIcon(_ icon: NSImage?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 24, height: 24)
        }
    }

    // MARK: Helpers

    private func commitSystem() {
        vm.endInteractive()
        vm.commitSystemVolume()
    }

    private func commitRow(_ id: String) {
        vm.endInteractive()
        vm.commitVolume(for: id)
    }
}

// MARK: - Slider

/// A capsule slider shaped like the one in the system sound panel. SwiftUI's own `Slider` has a
/// thin track and a rectangular knob, which looks out of place next to Control Center.
struct MixerSlider: View {

    @Binding var value: Double          // 0...100
    var height: CGFloat = 22
    /// Glyphs drawn inside the track's ends, as the system panel does. `nil` for the compact rows.
    var leadingSymbol: String?
    var trailingSymbol: String?
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let knob = height
            let travel = max(geo.size.width - knob, 1)
            let x = travel * CGFloat(min(max(value, 0), 100) / 100)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))

                Capsule()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: x + knob / 2)

                symbols

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let position = min(max(gesture.location.x - knob / 2, 0), travel)
                        value = Double(position / travel) * 100
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: height)
    }

    @ViewBuilder
    private var symbols: some View {
        if leadingSymbol != nil || trailingSymbol != nil {
            HStack {
                symbol(leadingSymbol)
                Spacer()
                symbol(trailingSymbol)
            }
            .padding(.horizontal, 5)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func symbol(_ name: String?) -> some View {
        if let name {
            Image(systemName: name)
                .font(.system(size: height * 0.42))
                .foregroundColor(.primary.opacity(0.55))
        }
    }
}

#if DEBUG
struct SoundMixerSettingView_Previews: PreviewProvider {
    static var previews: some View {
        SoundMixerSettingView()
    }
}
#endif
