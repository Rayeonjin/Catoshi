import AppKit
import Combine
import Foundation
import SwiftUI

@main
struct CatoshiMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--unregister-login-item") {
            LoginItemManager.unregisterForUninstall()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: MenuPanelController!
    private var model: MarketModel!
    private let healthState = StatusBarHealthState()
    private var statusBarHost: PassthroughHostingView<StatusBarContentView>?
    private var cancellables = Set<AnyCancellable>()
    private var healthTimer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var screenSleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var statusBarLayoutScheduled = false
    private var cachedTooltipHealth: FeedHealth?
    private var cachedTooltipLanguage: AppLanguage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItemManager.performStartupMigration()
        model = MarketModel()
        configureStatusItem()
        configureControllers()
        observeStatusBarLayoutInputs()
        configureHealthAndWakeMonitoring()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Finder and Spotlight reopens should reveal the existing menu-bar app,
        // including when its status item is hidden by other menu-bar items.
        guard let button = statusItem?.button, let panelController else { return false }
        sender.activate(ignoringOtherApps: true)
        panelController.show(relativeTo: button)
        return true
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            let initialHealth = feedHealth(model: model)
            healthState.update(initialHealth)
            updateStatusTooltip(health: initialHealth)
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        installStatusBarView()
    }

    private func configureControllers() {
        panelController = MenuPanelController(model: model)
    }

    private func observeStatusBarLayoutInputs() {
        // Keep these subscriptions explicit: each group changes the intrinsic width
        // of the custom NSStatusItem view, but not all of them change menuBarLayoutSignature.
        observeLayout(model.$menuBarLayoutSignature.removeDuplicates())

        observeLayout(
            Publishers.CombineLatest3(
                model.$showMenuBarBinanceSparkline.removeDuplicates(),
                model.$showMenuBarUpbitSparkline.removeDuplicates(),
                model.$showMenuBarPremiumSparkline.removeDuplicates()
            )
        )

        observeLayout(
            Publishers.CombineLatest3(
                model.$showMenuBarBinance24h.removeDuplicates(),
                model.$showMenuBarUpbit24h.removeDuplicates(),
                model.$showMenuBarPremium24h.removeDuplicates()
            )
        )

        observeLayout(model.$appLanguage.removeDuplicates())
        observeLayout(model.$showCatoshi.removeDuplicates())

        observeLayout(
            Publishers.CombineLatest3(
                model.$showMenuBarBinance.removeDuplicates(),
                model.$showMenuBarUpbit.removeDuplicates(),
                model.$showMenuBarPremium.removeDuplicates()
            )
        )
    }

    private func observeLayout<P: Publisher>(_ publisher: P) where P.Failure == Never {
        publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleStatusBarLayout()
            }
            .store(in: &cancellables)
    }

    private func scheduleStatusBarLayout() {
        guard !statusBarLayoutScheduled else { return }
        statusBarLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusBarLayoutScheduled = false
            self.layoutStatusBarView()
        }
    }

    private func configureHealthAndWakeMonitoring() {
        startHealthTimer()

        // Some Macs report display sleep before system sleep, while others can enter
        // system sleep without a useful screen transition. Observe both and route them
        // through idempotent helpers so runtime work is reliably paused on every model.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.enterLowActivityState() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeActiveState(afterSystemWake: true) }
        }

        screenSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.enterLowActivityState() }
        }

        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeActiveState(afterSystemWake: false) }
        }
    }

    private func enterLowActivityState() {
        // Hidden panels and their focused REST loops have no value while no display is
        // visible. Closing also releases the off-screen SwiftUI hosting tree.
        panelController?.close()
        stopHealthTimer()
        model.setDisplayActive(false)
    }

    private func resumeActiveState(afterSystemWake: Bool) {
        startHealthTimer()
        if afterSystemWake {
            model.handleSystemWake()
        } else {
            model.setDisplayActive(true)
        }
        refreshHealthPresentation()
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        // One shared low-frequency supervisor replaces per-socket watchdog timers.
        // It is suspended entirely while the display sleeps.
        let timer = Timer.scheduledTimer(
            timeInterval: CatoshiRuntimePolicy.feedHealthInterval,
            target: self,
            selector: #selector(refreshHealthIndicator),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = CatoshiRuntimePolicy.feedHealthTolerance
        healthTimer = timer
    }

    private func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForTermination()
        stopHealthTimer()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let screenSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screenSleepObserver)
        }
        if let screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screenWakeObserver)
        }
    }

    private func installStatusBarView() {
        guard let button = statusItem.button else { return }

        let host = PassthroughHostingView(
            rootView: StatusBarContentView(model: model, healthState: healthState)
        )
        host.translatesAutoresizingMaskIntoConstraints = true
        button.addSubview(host)
        statusBarHost = host
        layoutStatusBarView()
    }

    private func layoutStatusBarView() {
        guard let button = statusItem.button, let host = statusBarHost else { return }

        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let width = max(1, ceil(fitting.width) + 8)
        let widthChanged = abs(statusItem.length - width) > 0.5
        if widthChanged {
            statusItem.length = width
        }

        let height = button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness
        let targetFrame = NSRect(x: 4, y: 0, width: max(1, width - 8), height: height)
        if !NSEqualRects(host.frame, targetFrame) {
            host.frame = targetFrame
        }
        updateStatusTooltip()

        if widthChanged, panelController?.isShown == true {
            panelController.reposition(relativeTo: button)
        }
    }

    @objc
    private func refreshHealthIndicator() {
        let now = Date()
        refreshHealthPresentation(now: now)
        model.superviseFeedHealth(now: now)
    }

    private func refreshHealthPresentation(now: Date = Date()) {
        let health = feedHealth(model: model, now: now)
        healthState.update(health)
        updateStatusTooltip(health: health)
    }

    private func updateStatusTooltip(health: FeedHealth? = nil) {
        guard let button = statusItem?.button else { return }
        let resolvedHealth = health ?? feedHealth(model: model)
        let language = model.appLanguage
        guard cachedTooltipHealth != resolvedHealth || cachedTooltipLanguage != language else { return }
        cachedTooltipHealth = resolvedHealth
        cachedTooltipLanguage = language
        button.toolTip = resolvedHealth.toolTip(language)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        panelController.toggle(relativeTo: button)
    }
}

@MainActor
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MenuPanelController {
    private let panel: MenuPanel
    private static let panelWidth: CGFloat = 500
    private static let initialPanelHeight: CGFloat = 320
    private var preferredHeightTask: Task<Void, Never>?
    private var lastSelectedTab: MainPopoverTab = .prices
    private static let menuBarGap: CGFloat = 4
    private static let screenMargin: CGFloat = 8
    private weak var anchorButton: NSStatusBarButton?
    private var outsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?
    private let model: MarketModel
    private let marketContext: MarketContextModel
    private var appearanceCancellable: AnyCancellable?

    var isShown: Bool { panel.isVisible }

    init(model: MarketModel) {
        self.model = model
        self.marketContext = model.marketContext
        let size = NSSize(width: Self.panelWidth, height: Self.initialPanelHeight)

        panel = MenuPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Keep the always-on panel shell lightweight. The SwiftUI popover tree is
        // attached only while visible and released on close, so hidden price/cat
        // updates cannot invalidate an off-screen view hierarchy.
        panel.setContentSize(size)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        applyAppearance(model.appAppearance)
        appearanceCancellable = model.$appAppearance
            .removeDuplicates()
            .sink { [weak self] appearance in
                Task { @MainActor in
                    self?.applyAppearance(appearance)
                }
            }
    }

    private func applyAppearance(_ appearance: AppAppearance) {
        panel.appearance = appearance.nsAppearance
        panel.contentView?.needsDisplay = true
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isShown {
            close()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        installContentIfNeeded()
        anchorButton = button
        reposition(relativeTo: button)
        marketContext.setPopoverVisible(true)
        model.setPopoverVisible(true)
        panel.makeKeyAndOrderFront(nil)
        startEventMonitors()
    }

    func close() {
        marketContext.setPopoverVisible(false)
        model.setPopoverVisible(false)
        preferredHeightTask?.cancel()
        preferredHeightTask = nil
        panel.orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.panel.isVisible else { return }
            self.panel.contentViewController = nil
        }
        stopEventMonitors()
    }

    private func installContentIfNeeded() {
        guard panel.contentViewController == nil else { return }

        let rootView = MarketPopover(
            model: model,
            initialTab: lastSelectedTab,
            onPreferredHeightChange: { [weak self] height in
                self?.setPreferredHeight(height)
            },
            onSelectedTabChange: { [weak self] tab in
                self?.lastSelectedTab = tab
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.panelWidth, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 16
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
        panel.contentViewController = hostingController
    }

    func reposition(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        applyPanelFrame(height: panel.frame.height, relativeTo: button)
    }

    private func setPreferredHeight(_ requestedHeight: CGFloat) {
        // SwiftUI can report a couple of transient heights while a segmented tab is
        // being replaced. Coalesce those layout passes so the NSPanel only applies
        // the final content height, which prevents a visible shrink-expand flash.
        let targetHeight = ceil(requestedHeight)
        preferredHeightTask?.cancel()
        preferredHeightTask = Task { @MainActor [weak self] in
            try? await Task<Never, Never>.sleep(nanoseconds: 12_000_000)
            guard !Task.isCancelled, let self else { return }
            self.applyPreferredHeight(targetHeight)
        }
    }

    private func applyPreferredHeight(_ requestedHeight: CGFloat) {
        guard abs(panel.frame.height - requestedHeight) > 0.5 else { return }

        if let anchorButton {
            // Resizing a transparent rounded NSPanel through animator() causes a
            // brief background flash on some Macs. Snap the bottom edge to the new
            // intrinsic height after the coalesced layout pass instead.
            applyPanelFrame(height: requestedHeight, relativeTo: anchorButton)
        } else {
            panel.setContentSize(NSSize(width: Self.panelWidth, height: requestedHeight))
        }
    }

    private func applyPanelFrame(height requestedHeight: CGFloat, relativeTo button: NSStatusBarButton) {
        guard let statusWindow = button.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = statusWindow.convertToScreen(buttonRectInWindow)
        let screenFrame = (statusWindow.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: Self.panelWidth, height: requestedHeight)

        // Keep the top edge pinned just below the menu-bar item while each tab chooses
        // its own content height. Clamp only for unusually short displays.
        let availableHeight = max(240, buttonRectOnScreen.minY - screenFrame.minY - Self.menuBarGap - Self.screenMargin)
        let height = min(max(240, requestedHeight), availableHeight)
        let size = NSSize(width: Self.panelWidth, height: height)

        let idealX = buttonRectOnScreen.midX - size.width / 2
        let minX = screenFrame.minX + Self.screenMargin
        let maxX = max(minX, screenFrame.maxX - size.width - Self.screenMargin)
        let x = min(max(idealX, minX), maxX)
        let y = buttonRectOnScreen.minY - size.height - Self.menuBarGap
        let targetFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

        panel.setFrame(targetFrame, display: true)
    }

    private func startEventMonitors() {
        stopEventMonitors()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in
                self?.close()
            }
            return nil
        }
    }

    private func stopEventMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }
}
