//
//  AppDelegate.swift
//  pullBar
//
//  Created by Pavel Makhov on 2021-11-15.
//

import Cocoa
import Defaults
import SwiftUI
import Foundation
import KeychainAccess

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    let ghClient = GitHubClient()
    var statusBarItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu: NSMenu = NSMenu()
    
    var preferencesWindow: NSWindow!
    var aboutWindow: NSWindow!
    
    var timer: Timer? = nil

    var isRefreshing = false
    var lastRefreshed: Date? = nil
    var refreshFooter: RefreshFooterView? = nil
    var isMenuOpen = false
    // Option alternates inserted into an open menu make AppKit indent the standard items, so they wait for it to close.
    var pendingAlternates: [(alternate: NSMenuItem, primary: NSMenuItem)] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        migrateCategoriesIfNeeded()

        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.windowClosed), name: NSWindow.willCloseNotification, object: nil)

        guard let statusButton = statusBarItem.button else { return }
        let icon = NSImage(named: "git-pull-request")
        let size = NSSize(width: 16, height: 16)
        icon?.isTemplate = true
        icon?.size = size
        statusButton.image = icon
        statusButton.imagePosition = NSControl.ImagePosition.imageLeft
        
        statusBarItem.menu = menu
        menu.delegate = self

        timer = Timer.scheduledTimer(
            timeInterval: Double(Defaults[.refreshRate] * 60),
            target: self,
            selector: #selector(refreshMenu),
            userInfo: nil,
            repeats: true
        )
        timer?.fire()
        RunLoop.main.add(timer!, forMode: .common)
        NSApp.setActivationPolicy(.accessory)


        // Insert code here to initialize your application
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @objc
    func openLink(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(sender.representedObject as! URL)
    }

    func migrateCategoriesIfNeeded() {
        if Defaults[.categoriesSchemaVersion] < 1 {
            Defaults[.categoriesSchemaVersion] = 1
            migrateLegacyCategories()
        }
        // Filters used to store a `<username>` placeholder; GitHub search resolves `@me` itself.
        if Defaults[.categoriesSchemaVersion] < 2 {
            Defaults[.categoriesSchemaVersion] = 2
            Defaults[.categories] = Defaults[.categories].map {
                var category = $0
                category.filter = category.filter.replacingOccurrences(of: "<username>", with: "@me")
                return category
            }
        }
        // The global "Additional Query" setting was appended to every search; move it into each filter.
        if Defaults[.categoriesSchemaVersion] < 3 {
            Defaults[.categoriesSchemaVersion] = 3
            let additionalQuery = Defaults[.legacyAdditionalQuery].trimmingCharacters(in: .whitespacesAndNewlines)
            if !additionalQuery.isEmpty {
                Defaults[.categories] = Defaults[.categories].map {
                    var category = $0
                    category.filter = "\(category.filter) \(additionalQuery)"
                    return category
                }
            }
            Defaults.reset(.legacyAdditionalQuery)
        }
    }

    /// One-time migration of the legacy per-type toggles and counter choice into
    /// the user-managed `categories` list and `counterSelection`. Fresh installs
    /// (no persisted legacy settings) keep the default categories instead.
    private func migrateLegacyCategories() {
        let userDefaults = UserDefaults.standard
        let hasLegacySettings = ["showAssigned", "showCreated", "showRequested", "counterType"]
            .contains { userDefaults.object(forKey: $0) != nil }
        guard hasLegacySettings else { return }

        let counterTemplate: BuiltinTemplate?
        switch Defaults[.legacyCounterType] {
        case "none": counterTemplate = nil
        case "assigned": counterTemplate = .assigned
        case "created": counterTemplate = .created
        default: counterTemplate = .reviewRequested
        }

        // Seed the categories list from the legacy toggles, preserving order. A
        // counter that pointed at a hidden section adds that section, since the
        // counter can only show a category's count.
        let enabled: [BuiltinTemplate: Bool] = [
            .assigned: Defaults[.showAssigned],
            .created: Defaults[.showCreated],
            .reviewRequested: Defaults[.showRequested],
        ]
        let seeded = [BuiltinTemplate.assigned, .created, .reviewRequested]
            .filter { enabled[$0] == true || $0 == counterTemplate }
        Defaults[.categories] = seeded.map { $0.makeSeedCategory() }
        Defaults[.counterSelection] = counterTemplate?.seedId ?? SearchCategory.counterNone
    }

    @objc
    func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refreshFooter?.update()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        for (alternate, primary) in pendingAlternates {
            guard let primaryMenu = primary.menu else { continue }
            primaryMenu.insertItem(alternate, at: primaryMenu.index(of: primary) + 1)
        }
        pendingAlternates = []
    }
}

extension AppDelegate {
    @objc
    func refreshMenu() {
        NSLog("Refreshing menu")
        guard !isRefreshing else { return }

        if (GhCli.token == "") {
            let staging = NSMenu()
            addMenuFooterItems(to: staging)
            replaceMenuItems(with: staging)
            return
        }

        isRefreshing = true
        refreshFooter?.isRefreshing = true


        let categories = Defaults[.categories].filter {
            !$0.filter.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let counter = Defaults[.counterSelection]

        var pullsByCategory: [String: [Edge]] = [:]

        let group = DispatchGroup()

        for category in categories {
            group.enter()
            ghClient.getPulls(filter: category.filter) { pulls in
                pullsByCategory[category.id, default: []].append(contentsOf: pulls)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.isRefreshing = false
            self.lastRefreshed = Date()

            // An empty NSMenu will not open, so hold the previous items until
            // the new ones are ready to replace them.
            let staging = NSMenu()
            self.pendingAlternates = []
            self.statusBarItem.button?.title = ""

            // Only categories that actually have pull requests are rendered.
            let visibleCategories = categories.filter { !(pullsByCategory[$0.id] ?? []).isEmpty }

            for (index, category) in visibleCategories.enumerated() {
                let pulls = pullsByCategory[category.id] ?? []
                let headerTitle = "\(category.displayName) (\(pulls.count))"
                let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
                header.attributedTitle = PullMenuTitle.sectionHeader(name: category.displayName, count: pulls.count)

                if category.asSubmenu {
                    let parent = header
                    let submenu = NSMenu()
                    for pull in pulls {
                        self.addMenuItems(pull: pull, to: submenu)
                    }
                    parent.submenu = submenu
                    staging.addItem(parent)
                } else {
                    staging.addItem(header)
                    for pull in pulls {
                        self.addMenuItems(pull: pull, to: staging)
                    }
                }

                // Keep adjacent submenu categories grouped: no separator between
                // two consecutive submenu items.
                let next = index + 1 < visibleCategories.count ? visibleCategories[index + 1] : nil
                let groupedWithNext = category.asSubmenu && (next?.asSubmenu ?? false)
                if !groupedWithNext {
                    staging.addItem(.separator())
                }
            }

            let counterCount = (pullsByCategory[counter] ?? []).count
            if counterCount > 0 {
                self.statusBarItem.button?.title = String(counterCount)
            }

            self.addMenuFooterItems(to: staging)
            self.replaceMenuItems(with: staging)
        }
    }

    func replaceMenuItems(with staging: NSMenu) {
        let items = staging.items
        staging.removeAllItems()
        for (index, item) in items.enumerated() {
            menu.insertItem(item, at: index)
        }
        while menu.numberOfItems > items.count {
            menu.removeItem(at: items.count)
        }
    }

    func addMenuItems(pull: Edge, to menu: NSMenu) {
        let issueItem = createMenuItem(pull: pull)
        menu.addItem(issueItem)

        // Option alternate: same row as the pull request, with the first line replaced by "Copy Link #123"
        let copyTitle = NSMutableAttributedString(attributedString: issueItem.attributedTitle ?? NSAttributedString(string: issueItem.title))
        let firstLineEnd = (copyTitle.string as NSString).range(of: "\n").location
        let firstLine = NSMutableAttributedString(string: "")
            .appendString(string: "Copy Link", color: .labelColor, font: PullMenuTitle.titleFont)
            .appendString(string: "  #" + String(pull.node.number), color: .secondaryLabelColor, font: PullMenuTitle.detailFont)
        copyTitle.replaceCharacters(in: NSRange(location: 0, length: firstLineEnd == NSNotFound ? copyTitle.length : firstLineEnd), with: firstLine)

        let copyItem = NSMenuItem(title: "", action: #selector(copyLink), keyEquivalent: "")
        copyItem.attributedTitle = copyTitle
        copyItem.isAlternate = true
        copyItem.keyEquivalentModifierMask = [.option]
        copyItem.representedObject = pull.node.url
        copyItem.toolTip = pull.node.url.absoluteString
        if isMenuOpen {
            pendingAlternates.append((alternate: copyItem, primary: issueItem))
        } else {
            menu.addItem(copyItem)
        }

        setAvatar(pull: pull, for: [issueItem, copyItem])
    }

    func setAvatar(pull: Edge, for items: [NSMenuItem]) {
        guard Defaults[.showAvatar] else { return }

        // Set default image initially
        let defaultImage = NSImage(named: "person")!
        let resizedDefaultImage = resizeImage(image: defaultImage, size: NSSize(width: 36.0, height: 36.0))
        items.forEach { $0.image = resizedDefaultImage }

        // Load avatar asynchronously if available
        if let author = pull.node.author, let imageURL = author.avatarUrl {
            NSImage.loadImageAsync(fromURL: imageURL) { loadedImage in
                guard let loadedImage = loadedImage else { return }

                loadedImage.cacheMode = NSImage.CacheMode.always
                let resizedImage = self.circularImage(image: loadedImage, diameter: 36.0)
                items.forEach { $0.image = resizedImage }
            }
        }
    }
    
    func createMenuItem(pull: Edge) -> NSMenuItem {
        let issueItem = NSMenuItem(title: "", action: #selector(self.openLink), keyEquivalent: "")
        let checks = addChecksSubmenu(pull: pull, to: issueItem)

        issueItem.attributedTitle = PullMenuTitle.title(for: pull, checks: checks, showLabels: Defaults[.showLabels])
        if pull.node.title.count > PullMenuTitle.titleLength {
            issueItem.toolTip = pull.node.title
        }
        issueItem.representedObject = pull.node.url

        return issueItem
    }

    /// Adds a submenu listing the pull request's checks, and returns their states for the row's summary pill.
    func addChecksSubmenu(pull: Edge, to issueItem: NSMenuItem) -> [CheckState] {
        var checks: [CheckState] = []

        if let commits = pull.node.commits {

            if let checkSuites = commits.nodes[0].commit.checkSuites {

                if checkSuites.nodes.count > 0 {
                    issueItem.submenu = NSMenu()
                }
                for checkSuite in checkSuites.nodes {
                    
                    if checkSuite.checkRuns.nodes.count > 0 {
                        issueItem.submenu?.addItem(withTitle: checkSuite.app?.name ?? "empty", action: nil, keyEquivalent: "")
                    }
                    for check in checkSuite.checkRuns.nodes {
                        
                        let buildItem = NSMenuItem(title: check.name, action: #selector(self.openLink), keyEquivalent: "")
                        buildItem.representedObject = check.detailsUrl
                        buildItem.toolTip = check.conclusion ?? "IN_PROGRESS"
                        buildItem.image = checkImage(for: check.conclusion)
                        checks.append(CheckState(conclusion: check.conclusion))
                        
                        issueItem.submenu?.addItem(buildItem)
                    }
                }
            }
            
            else if let statusCheckRollup = commits.nodes[0].commit.statusCheckRollup {
                
                if statusCheckRollup.contexts.nodes.count > 0 {
                    issueItem.submenu = NSMenu()
                }
                
                for check in statusCheckRollup.contexts.nodes {
                    let itemTitle = NSMutableAttributedString()
                    itemTitle.appendString(string: check.name ?? check.context ?? "<empty>", color: NSColor(.primary))
                    itemTitle.appendNewLine()
                        .appendString(string: check.description ?? check.title ?? "<empty>", color: NSColor(.secondary))
                    
                    let buildItem = NSMenuItem(title: "", action: #selector(AppDelegate.openLink), keyEquivalent: "")
                    buildItem.attributedTitle = itemTitle
                    
                    buildItem.representedObject = check.detailsUrl ?? URL.init(string:check.targetUrl ?? "")
                    
                    let status = check.conclusion ?? check.state ?? ""
                    buildItem.toolTip = status.isEmpty ? "IN_PROGRESS" : status
                    buildItem.image = checkImage(for: status)
                    checks.append(CheckState(conclusion: status))
                    issueItem.submenu?.addItem(buildItem)
                }
            }
        }

        return checks
    }

    /// Submenu icon for a check run conclusion or status context state. `nil` or empty means the check is still running.
    func checkImage(for status: String?) -> NSImage {
        switch status {
        case "SUCCESS":
            return NSImage(named: "check-circle-fill")!.tint(color: NSColor(named: "green")!)
        case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ERROR":
            return NSImage(named: "x-circle-fill")!.tint(color: NSColor(named: "red")!)
        case nil, "", "PENDING":
            return NSImage(named: "dot-fill")!.tint(color: NSColor(named: "yellow")!)
        case "ACTION_REQUIRED", "EXPECTED":
            return NSImage(named: "issue-draft")!.tint(color: NSColor(named: "yellow")!)
        case "NEUTRAL", "SKIPPED", "CANCELLED", "STALE":
            let image = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: nil)!
            image.size = NSImage(named: "question")!.size
            return image.tint(color: NSColor.gray)
        default:
            return NSImage(named: "question")!.tint(color: NSColor.gray)
        }
    }

    func addMenuFooterItems(to menu: NSMenu) {
        let footer = RefreshFooterView { [weak self] in
            self?.refreshMenu()
        }
        footer.lastRefreshed = lastRefreshed
        let footerItem = NSMenuItem()
        footerItem.view = footer
        menu.addItem(footerItem)
        refreshFooter = footer

        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences...", action: #selector(self.openPrefecencesWindow), keyEquivalent: "")
        // Remove for app store release
//        menu.addItem(withTitle: "Check for updates...", action: #selector(self.checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "About PullBar", action: #selector(self.openAboutWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(self.quit), keyEquivalent: "")
    }
    
    @objc
    func openPrefecencesWindow(_: NSStatusBarButton?) {
        NSLog("Open preferences window")
        let contentView = PreferencesView()
        if preferencesWindow != nil {
            preferencesWindow.close()
        }
        preferencesWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false
        )
        
        preferencesWindow.title = "Preferences"
        preferencesWindow.contentView = NSHostingView(rootView: contentView)
        preferencesWindow.makeKeyAndOrderFront(nil)
        preferencesWindow.styleMask.remove(.resizable)
        
        // allow the preference window can be focused automatically when opened
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        let controller = NSWindowController(window: preferencesWindow)
        controller.showWindow(self)
        
        preferencesWindow.center()
        preferencesWindow.orderFrontRegardless()
    }
    
    @objc
    func openAboutWindow(_: NSStatusBarButton?) {
        NSLog("Open about window")
        let contentView = AboutView()
        if aboutWindow != nil {
            aboutWindow.close()
        }
        aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 500),
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false
        )
        
        aboutWindow.title = "About"
        aboutWindow.contentView = NSHostingView(rootView: contentView)
        aboutWindow.makeKeyAndOrderFront(nil)
        aboutWindow.styleMask.remove(.resizable)
        
        // allow the preference window can be focused automatically when opened
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        let controller = NSWindowController(window: aboutWindow)
        controller.showWindow(self)
        
        aboutWindow.center()
        aboutWindow.orderFrontRegardless()
    }
    
    @objc
    func windowClosed(notification: NSNotification) {
        let window = notification.object as? NSWindow
        if let windowTitle = window?.title {
            if (windowTitle == "Preferences") {
                timer?.invalidate()
                timer = Timer.scheduledTimer(
                    timeInterval: Double(Defaults[.refreshRate] * 60),
                    target: self,
                    selector: #selector(refreshMenu),
                    userInfo: nil,
                    repeats: true
                )
                timer?.fire()
            }
        }
    }
    
    @objc
    func quit() {
        NSLog("User click Quit")
        NSApplication.shared.terminate(self)
    }
    
    @objc
    func checkForUpdates(_: NSStatusBarButton?) {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        ghClient.getLatestRelease { latestRelease in
            if let latestRelease = latestRelease {
                let versionComparison = currentVersion.compare(latestRelease.name.replacingOccurrences(of: "v", with: ""), options: .numeric)
                if versionComparison == .orderedAscending {
                    self.downloadNewVersionDialog(link: latestRelease.assets[0].browserDownloadUrl)
                } else {
                    self.dialogWithText(text: "You have the latest version installed!")
                }
            }
        }
    }
    
    func dialogWithText(text: String) -> Void {
        let alert = NSAlert()
        alert.messageText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    func downloadNewVersionDialog(link: String) -> Void {
        let alert = NSAlert()
        alert.messageText = "New version is available!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        let pressedButton = alert.runModal()
        if (pressedButton == .alertFirstButtonReturn) {
            NSWorkspace.shared.open(URL(string: link)!)
        }
    }
    
    /// Resizes an NSImage to the specified size
    func resizeImage(image: NSImage, size: NSSize) -> NSImage {
        if image.size.height == size.height && image.size.width == size.width {
            return image
        }
        
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: image.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    func circularImage(image: NSImage, diameter: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }
}
