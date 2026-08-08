//
//  SoundMixerPanelView.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/07/13.
//

import Defines
import SwiftUI
import Utilities

// MARK: - Panel

/// The mixer inside the switch list popover, built like ``AuthenticatorPanelView``: a header row
/// that expands in place. There is no menu bar item and no settings page for it, so the whole
/// feature lives behind the one icon OnlySwitch already owns.
struct SoundMixerPanelView: View {

    @ObservedObject private var vm = SoundMixerVM.shared
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
                .opacity(0.25)
                .frame(height: 1)

            if isExpanded {
                content
            }
        }
        // Polls while the popover is open, so the header count is right before expanding too.
        .onAppear { vm.startAutoRefresh() }
        .onDisappear { vm.stopAutoRefresh() }
    }

    private var headerRow: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18))
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .foregroundColor(.accentColor)
                .padding(.trailing, 8)

            HStack(spacing: 6) {
                Text("Sound Mixer".localized())
                    .font(.system(size: 14))
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Text(appSummary)
                .foregroundColor(.gray)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring()) { isExpanded.toggle() }
        }
        .frame(height: 45)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            MixerSlider(value: $vm.systemVolume,
                        height: 22,
                        leadingSymbol: "speaker.fill",
                        trailingSymbol: "speaker.wave.3.fill") { editing in
                editing ? vm.beginInteractive() : commitSystem()
            }
            .onChange(of: vm.systemVolume) { _, _ in
                vm.applySystemVolumeWhileDragging()
            }
            .padding(.horizontal, 15)
            .padding(.top, 10)

            if vm.rows.isEmpty {
                Text("No controllable apps are running".localized())
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 15)
            } else {
                sectionHeader("Apps".localized())
                VStack(spacing: 10) {
                    ForEach($vm.rows) { $row in
                        appRow($row)
                    }
                }
                .padding(.horizontal, 15)
            }

            if let device = vm.outputDevice {
                sectionHeader("Output".localized())
                outputRow(device)
            }

            Button {
                vm.openSoundSettings()
            } label: {
                Text("Sound Settings…".localized())
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 15)
            .padding(.bottom, 10)
        }
    }

    private var appSummary: String {
        let count = vm.rows.count
        if count == 0 { return "" }
        if count == 1 { return "1 app".localized() }
        return String(format: "%lld apps".localized(), count)
    }

    // MARK: Rows

    private func appRow(_ row: Binding<SoundMixerVM.AppRow>) -> some View {
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
        .padding(.horizontal, 15)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 15)
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
struct SoundMixerPanelView_Previews: PreviewProvider {
    static var previews: some View {
        SoundMixerPanelView()
            .frame(width: Layout.popoverWidth)
    }
}
#endif
