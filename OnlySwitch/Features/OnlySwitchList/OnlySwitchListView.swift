//
//  ContentView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import AppKit
import ComposableArchitecture
import Defines
import Authenticator
import SwiftUI
import LaunchAtLogin
import Switches
import Utilities
import OnlyAgent
import Aphrodite
import XcodeCleaner
import AppUninstaller
import Screenshots

enum Focusable: Hashable {
  case none
  case row(index: Int)
}

struct OnlySwitchListView: View {
    private let onPanelSizeChange: @MainActor (CGSize) -> Void
    private let onOutsideClickRetentionChanged: @MainActor (Bool) -> Void
    private let onSectionSelectionChanged: @MainActor (SectionBar.Section) -> Void
    @EnvironmentObject var switchVM:SwitchListVM
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var distanceY:CGFloat = 0
    @State private var movingIndex = -1
    @State private var hoverIndex = -1
    @ObservedObject private var playerItem = RadioStationSwitch.shared.playerItem
    @ObservedObject private var authenticatorStore = AuthenticatorStore.shared
    @ObservedObject private var soundMixerVM = SoundMixerVM.shared
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    @FocusState var focusedBar: Focusable?
    @State private var selectedSection: SectionBar.Section = .controls
    @State private var measuredContentHeight: CGFloat?
    @State private var measuredChromeHeight: CGFloat = 144
    @State private var maximumPanelHeight = NSScreen.main?.visibleFrame.height ?? CGFloat(700)
    @State private var presentedPanelHeight: CGFloat?
    @State private var aphroditeStore: StoreOf<AphroditeReducer>
    private let screenshotSectionRevealStore = SettingsVM.shared.screenshotSectionRevealStore
    @AppStorage(UserDefaults.Key.showClaudeUsageTab) private var showClaudeUsageTab = true
    @AppStorage(UserDefaults.Key.showCodexUsageTab) private var showCodexUsageTab = true
    @AppStorage(UserDefaults.Key.showSystemMonitorTab) private var showSystemMonitorTab = true
    @AppStorage(UserDefaults.Key.showAphroditeTab) private var showAphroditeTab = true
    @AppStorage(UserDefaults.Key.showXcodeCleanerTab) private var showXcodeCleanerTab = true
    @AppStorage(UserDefaults.Key.showAppUninstallerTab) private var showAppUninstallerTab = true
    @AppStorage(UserDefaults.Key.showScreenshotsTab) private var showScreenshotsTab = true

    let columns = [
        GridItem(.fixed(Layout.popoverWidth - 40)),
        GridItem(.fixed(Layout.popoverWidth - 40))
    ]

    init(onPanelSizeChange: @escaping @MainActor (CGSize) -> Void = { _ in }, onOutsideClickRetentionChanged: @escaping @MainActor (Bool) -> Void = { _ in }, onSectionSelectionChanged: @escaping @MainActor (SectionBar.Section) -> Void = { _ in }) {
        self.onPanelSizeChange = onPanelSizeChange
        self.onOutsideClickRetentionChanged = onOutsideClickRetentionChanged
        self.onSectionSelectionChanged = onSectionSelectionChanged
        _aphroditeStore = State(initialValue: Store(initialState: .init()) { AphroditeReducer() })
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer()
                BluredSoundWave(width: listWidth, height: soundWaveHeight)
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                    .isHidden(
                        selectedSection != .controls || !switchVM.soundWaveEffectDisplay || !playerItem.isPlaying,
                        remove: true
                    )
            }
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if SwitchListAppearance(rawValue: switchVM.currentAppearance) == .dual {
                        bottomBar.opacity(0.7).padding(.top, 20)
                    }
                    if SectionBar.shouldShowBar(for: sections) {
                        SystemMonitorSectionBar(
                            sections: sections,
                            selection: $selectedSection,
                            visibleSegmentLimit: SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single
                                ? SectionBar.singleColumnVisibleSegmentLimit : nil
                        )
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in Color.clear.preference(key: PanelChromeHeightKey.self, value: proxy.size.height) })

                ScrollView {
                    Group {
                        switch selectedSection {
                        case .controls:
                            if switchVM.currentAppearance == SwitchListAppearance.single.rawValue {
                                singleSwitchList
                            } else {
                                dualcolumnList
                            }
                        case .authenticator:
                            AuthenticatorPanelView()
                        case .soundMixer:
                            SoundMixerPanelView()
                        case .systemMonitor:
                            SystemMonitorPanelContainer()
                        case .claudeUsage:
                            if #available(macOS 14.0, *) {
                                ClaudeUsagePanelContainer(managesScrolling: false)
                            }
                        case .codexUsage:
                            if #available(macOS 14.0, *) {
                                CodexUsagePanelContainer(managesScrolling: false)
                            }
                        case .xcodeCleaner:
                            XcodeCleanerView(store: SettingsVM.shared.xcodeCleanerStore, managesScrolling: false, compactPresentation: true)
                                .id(languageManager.currentLang)
                        case .appUninstaller:
                            AppUninstallerView(store: SettingsVM.shared.appUninstallerStore, managesScrolling: false, compactPresentation: true)
                                .id(languageManager.currentLang)
                        case .screenshots:
                            ScreenshotsView(store: SettingsVM.shared.screenshotsStore, compactPresentation: true)
                                .id(languageManager.currentLang)
                        case .aphrodite:
                            if #available(macOS 26.0, *) {
                                AphroditePanelView(
                                    store: aphroditeStore,
                                    maximumRunningHeight: max(0, maximumPanelHeight - measuredChromeHeight)
                                )
                            }
                            else { AphroditeUnavailableView() }
                        }
                    }
                    .background(GeometryReader { proxy in Color.clear.preference(key: PanelContentHeightKey.self, value: proxy.size.height) })
                }
                .frame(height: presentedScrollHeight)
                .padding(.bottom, 15)
                .padding(.horizontal, 0)
                VStack(spacing: 8) {
                    if switchVM.showAds {
                        recommendApp.opacity(0.8)
                    }
                    if SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single {
                        bottomBar
                    } else {
                        Color.clear.frame(height: 20)
                    }
                }
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in Color.clear.preference(key: PanelChromeHeightKey.self, value: proxy.size.height) })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPopover, object: nil)) { _ in
            Task {
                await switchVM.refreshData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .changeSettings, object: nil)) { _ in
            Task {
                await switchVM.refreshData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshSingleSwitchStatus, object: nil)) { n in
            if let type = n.object as? SwitchType {
                switchVM.refreshSingleSwitchStatus(type: type)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMenubarCollapse, object: nil)) { _ in
            switchVM.refreshSingleSwitchStatus(type: .hideMenubarIcons)
        }
        .onChange(of: screenshotSectionRevealStore.pendingHost) { _, _ in
            consumeScreenshotSectionReveal()
        }
        .onChange(of: sections) { _ in
            reconcileSectionSelection()
        }
        .onChange(of: selectedSection) { section in
            onSectionSelectionChanged(section)
            onOutsideClickRetentionChanged(!section.allowsOutsideClickDismissal)
        }
        .onPreferenceChange(PanelContentHeightKey.self) { measuredContentHeight = $0.isFinite && $0 >= 0 ? $0 : nil }
        .onPreferenceChange(PanelChromeHeightKey.self) { measuredChromeHeight = $0 + 15 }
        .background(PanelScreenHeightReader { maximumPanelHeight = $0 })
        .frame(width: listWidth, height: currentPanelHeight)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelRenderedSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PanelRenderedSizeKey.self) { size in
            guard size.width > 0, size.height > 0 else { return }
            onPanelSizeChange(size)
        }
        .onChange(of: adaptivePanelHeight) { updatePresentedPanelHeight(to: $0) }
        .onChange(of: accessibilityReduceMotion) { _ in
            updatePresentedPanelHeight(to: adaptivePanelHeight)
        }
        .onAppear {
            consumeScreenshotSectionReveal()
            presentedPanelHeight = adaptivePanelHeight
            onSectionSelectionChanged(selectedSection)
            onOutsideClickRetentionChanged(!selectedSection.allowsOutsideClickDismissal)
        }
    }

    private func consumeScreenshotSectionReveal() {
        guard screenshotSectionRevealStore.pendingHost == .popover else { return }
        if sections.contains(.screenshots) { selectedSection = .screenshots }
        screenshotSectionRevealStore.send(.consumed(.popover))
    }
    
    var singleSwitchList: some View {
        VStack(spacing:0) {
            ForEach(switchVM.allItemList.indices, id:\.self) { index in
                VStack {
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                            .shadow(color: .gray, radius: 2, x: 0, y: 1)
                            .isHidden(isMoverHidden(index: index), remove: true)

                        if let item = switchVM.allItemList[index] as? SwitchBarVM {
                            SwitchBarView().environmentObject(item)
                                .frame(height: Layout.singleSwitchHeight)
                        } else if let item = switchVM.allItemList[index] as? ShortcutsBarVM {
                            ShortcutsBarView().environmentObject(item)
                                .frame(height: Layout.singleSwitchHeight)
                        } else if let item = switchVM.allItemList[index] as? EvolutionBarVM {
                            EvolutionBarView().environmentObject(item)
                                .frame(height: Layout.singleSwitchHeight)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.top, 8)

                    Divider()
                        .opacity(0.25)
                        .frame(height: 1)
                }
                .background(
                    Color.accentColor
                    .shadow(color: Color(nsColor: .darkGray), radius: 1, x: 0, y: 1)
                    .opacity(0.15)
                    .isHidden(!itemHighlight(index: index))
                )
                .scaleEffect(itemScaleEffect(index: index))
                .focusReturnable(focusable: true, binding: $focusedBar, equals: .row(index: index)) {
                    if let item = switchVM.allItemList[index] as? SwitchBarVM {
                        item.switchType.doSwitch()
                    } else if let item = switchVM.allItemList[index] as? ShortcutsBarVM {
                        item.runShortCut()
                    } else if let item = switchVM.allItemList[index] as? EvolutionBarVM {
                        item.doSwitch()
                    }
                }
                .animation(.easeOut, value: focusedBar)
                .onHover{ isHovering in
                    if isHovering {
                        withAnimation(.easeOut) {
                            self.focusedBar = .row(index: index)
                        }
                    }
                }
                .offset(y: itemOffsetY(index: index))
                .gesture(
                    DragGesture()
                        .onChanged{ gesture in
                            guard switchVM.sortMode else { return }

                            movingIndex = index
                            let locationY = gesture.location.y
                            if self.distanceY == 0 && locationY != 0 {
                                NSCursor.closedHand.set()
                                print("set closeHand")
                            }

                            withAnimation{
                                self.distanceY = locationY
                            }

                            if abs(self.distanceY) > 10 {
                                let newIndex = movingIndex + Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / Int(Layout.singleSwitchHeight)
                                print("new index:\(newIndex), moving index:\(movingIndex), distance:\(self.distanceY)")
                            }
                        }
                        .onEnded{ gesture in
                            NSCursor.closedHand.pop()
                            if abs(self.distanceY) > 10 {
                                let indexOffset = Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / Int(Layout.singleSwitchHeight)

                                var newIndex = index + indexOffset
                                if newIndex < 0 {
                                    newIndex = 0
                                } else if newIndex > switchVM.allItemList.count {
                                    newIndex = switchVM.allItemList.count
                                }
                                move(from: IndexSet(integer: index), to: newIndex )
                                switchVM.saveOrder()
                            }
                            self.distanceY = 0
                            movingIndex = -1
                        }
                )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            if !isHovering {
                hoverIndex = -1
            }
        }
    }
    
    var dualcolumnList: some View {
        VStack(spacing: 0) {
            if switchVM.uncategoryItemList.count > 0 {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.uncategoryItemList.indices, id:\.self) { index in
                        HStack {
                            let item = switchVM.uncategoryItemList[index]
                            SwitchBarView().environmentObject(item)
                                    .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            
            if switchVM.audioItemList.count > 0 {
                HStack {
                    Rectangle().frame(height: 1)
                        .foregroundColor(.gray)
                    Text("AUDIO".localized())
                    Rectangle().frame(height: 1)
                        .foregroundColor(.gray)
                }.frame(height: 30)
                    .opacity(0.7)
                    .shadow(radius: 1)
                
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.audioItemList.indices, id: \.self) { index in
                        HStack {
                            let item = switchVM.audioItemList[index]
                            SwitchBarView().environmentObject(item)
                                    .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            if switchVM.cleanupItemList.count > 0 {
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                    Text("CLEANUP".localized())
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                }.frame(height:30)
                    .opacity(0.7)
                    .shadow(radius: 1)
                
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.cleanupItemList.indices, id: \.self) { index in
                        HStack {
                            let item = switchVM.cleanupItemList[index]
                            SwitchBarView()
                                .environmentObject(item)
                                .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            
            if switchVM.toolItemList.count > 0 {
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                    Text("TOOLS".localized())
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                }
                .frame(height:30)
                .opacity(0.7)
                .shadow(radius: 1)
                
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.toolItemList.indices, id:\.self) { index in
                        HStack {
                            let item = switchVM.toolItemList[index]
                            SwitchBarView()
                                .environmentObject(item)
                                .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            
            if switchVM.shortcutsList.count > 0 {
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                    
                    Text("ACTIONS".localized())
                    
                    Rectangle().frame(height: 1)
                        .foregroundColor(.gray)
                }
                .frame(height:30)
                .opacity(0.7)
                .shadow(radius: 1)
                
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.shortcutsList.indices, id:\.self) { index in
                        HStack {
                            let item = switchVM.shortcutsList[index]
                            ShortcutsBarView()
                                .environmentObject(item)
                                .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }

            if switchVM.evolutionList.count > 0 {
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                    Text("EVOLUTION")
                    Rectangle()
                        .frame(height: 1)
                }
                .frame(height:30)
                .opacity(0.7)
                .shadow(radius: 1)

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.evolutionList.indices, id:\.self) { index in
                        HStack {
                            let item = switchVM.evolutionList[index]
                            EvolutionBarView()
                                .environmentObject(item)
                                .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            
        }
        .padding(.horizontal, 0)
    }
    
    var recommendApp: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Ads) { ad in
                    Button {
                        if let qrcode = ad.qrcode {
                            QRCodeWindowController.shared.show(url: qrcode)
                        } else if let link = ad.link {
                            NSWorkspace.shared.open(link)
                        }
                    } label: {
                        AsyncImage(url: ad.imageURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: "app.dashed")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 45)
                        .cornerRadius(12)
                        .help(Text(ad.hint.localized()))
                        .accessibilityLabel(ad.hint.localized())
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.gray, lineWidth: 1)
                                .opacity(0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 45)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .foregroundColor(colorScheme == .dark ? Color(nsColor: NSColor.darkGray) : .white)
        )
        .padding(.horizontal, 15)
        .opacity(playerItem.isPlaying ? 0.5 : 1)
    }
    
    var bottomBar : some View {
        HStack {
            Button(action: {
                withAnimation {
                    switchVM.toggleSortMode()
                }
            }, label: {
                Image(systemName: switchVM.sortMode ? "line.3.horizontal.circle.fill" : "line.3.horizontal.circle")
                    .font(.system(size: 17))
            }).buttonStyle(.plain)
                .padding(10)
                .help(Text("Sort".localized()))
                .isHidden(selectedSection != .controls || SwitchListAppearance(rawValue: switchVM.currentAppearance) == .dual)
            
            Spacer()
            if playerItem.streamInfo == "" {
                HStack {
                    Text("Only Switch")
                        .fontWeight(.bold)
                        .padding(10)
                    
                    Text("v\(SystemInfo.majorVersion as! String)")
                        .offset(x:-10)
                }
                .transition(.move(edge: .bottom))
                
            } else {
                RollingText(text: playerItem.streamInfo,
                            leftFade: 16,
                            rightFade: 16,
                            startDelay: 3)
                .frame(height:20)
                .padding(10)
                .transition(.move(edge: .bottom))
            }
            
            
            Spacer()

            Button(action: {
                switchVM.showSettingsWindow()
            }, label: {
                Image(systemName: "gearshape.circle")
                    .font(.system(size: 17))
            }).buttonStyle(.plain)
                .padding(10)
                .help(Text("Settings".localized()))
        
        }
    }
    
    
    private var adaptivePanelHeight: CGFloat {
        AdaptivePanelHeightPolicy(
            minimumContentHeight: measuredContentHeight == nil ? 120 : 0,
            chromeHeight: measuredChromeHeight,
            maximumPanelHeight: maximumPanelHeight
        ).panelHeight(for: measuredContentHeight)
    }

    private var currentPanelHeight: CGFloat { presentedPanelHeight ?? adaptivePanelHeight }

    private var presentedScrollHeight: CGFloat { max(0, currentPanelHeight - measuredChromeHeight) }

    private func updatePresentedPanelHeight(to height: CGFloat) {
        if accessibilityReduceMotion {
            presentedPanelHeight = height
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                presentedPanelHeight = height
            }
        }
    }
    
    func move(from source: IndexSet, to destination: Int) {
        switchVM.moveItem(from: source, to: destination)
    }
    
    var listWidth:CGFloat {
        SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single ? Layout.popoverWidth : Layout.popoverWidth * 2 - 40
    }
    
    var soundWaveHeight:CGFloat {
        SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single ? Layout.soundWaveHeight : Layout.soundWaveHeight / 2
    }

    var shouldShowAuthenticatorPanel: Bool {
        authenticatorStore.enabled
    }

    var sections: [SectionBar.Section] {
        SectionBar.sections(
            authenticator: shouldShowAuthenticatorPanel,
            soundMixer: soundMixerVM.enabled,
            systemMonitor: showSystemMonitorTab,
            codexUsage: showCodexUsageTab,
            claudeUsage: showClaudeUsageTab,
            aphrodite: showAphroditeTab,
            xcodeCleaner: showXcodeCleanerTab,
            appUninstaller: showAppUninstallerTab,
            screenshots: showScreenshotsTab
        )
    }

    func reconcileSectionSelection() {
        if !sections.contains(selectedSection) {
            selectedSection = .controls
        }
    }
    
    func itemOffsetY(index:Int) -> CGFloat {
        var newIndex = index
        if abs(self.distanceY) > 10 {
            let indexOffset = Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / Int(Layout.singleSwitchHeight)
            print("indexOffset:\(indexOffset)")
            newIndex = movingIndex + indexOffset
        }
        if newIndex < 0 {
            newIndex = 0
        } else if newIndex > switchVM.allItemList.count {
            newIndex = switchVM.allItemList.count
        }
        
        
        if movingIndex == index {
            return distanceY
        } else if (distanceY > 0 && index < newIndex && index > movingIndex) || (distanceY < 0 && index >= newIndex && index < movingIndex)  {
            return -Layout.singleSwitchHeight * (distanceY / abs(distanceY))
        } else {
            return 0
        }
    }
    
    func currentCursor() -> NSCursor {
        if switchVM.sortMode {
            if distanceY != 0 {
                return NSCursor.closedHand
            } else {
                return NSCursor.openHand
            }
        } else {
            return NSCursor.arrow
        }
    }
    
    func isMoverHidden(index:Int) -> Bool {
        var hiddenSwitch = false
        if let item = switchVM.allItemList[index] as? SwitchBarVM {
            hiddenSwitch = item.isHidden
        }
        return !switchVM.sortMode || hiddenSwitch
    }
    
    func itemScaleEffect(index:Int) -> CGFloat {
        if switchVM.sortMode {
            return index == movingIndex ? 1.008 : 1.0
        } else {
            if focusedBar == .row(index: index) {
                return 1.008
            } else {
                return 1.0
            }
        }
    }
    
    func itemHighlight(index:Int) -> Bool {
        if switchVM.sortMode {
            return index == movingIndex ? true : false
        } else {
            return focusedBar == .row(index: index)
        }
    }
}

private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PanelChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private struct PanelRenderedSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        OnlySwitchListView()
            .frame(width: Layout.popoverWidth, height: Layout.popoverHeight)
            .environmentObject(SwitchListVM())
    }
}
#endif
