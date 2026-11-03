//
//  RefreshFooterView.swift
//  pullBar
//

import AppKit

/// Menu footer showing when pull requests were last fetched, with a refresh button.
/// Clicking a control inside a menu item view leaves the menu open, unlike selecting a regular item.
final class RefreshFooterView: NSView {

    var lastRefreshed: Date? {
        didSet { update() }
    }

    var isRefreshing = false {
        didSet { update() }
    }

    private let onRefresh: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()
    private let spinner = NSProgressIndicator()

    init(onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        autoresizingMask = .width

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        refreshButton.isBordered = false
        refreshButton.contentTintColor = .secondaryLabelColor
        refreshButton.toolTip = "Refresh"
        refreshButton.target = self
        refreshButton.action = #selector(refresh)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        for view in [statusLabel, refreshButton, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -8),
            refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: refreshButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
        ])
        update()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Recomputes the relative "Updated" text, which goes stale while the menu is closed.
    func update() {
        refreshButton.isHidden = isRefreshing
        if isRefreshing {
            statusLabel.stringValue = "Refreshing…"
            spinner.startAnimation(nil)
            return
        }

        spinner.stopAnimation(nil)
        guard let lastRefreshed else {
            statusLabel.stringValue = "Not updated yet"
            return
        }
        let elapsed = lastRefreshed.getElapsedInterval()
        statusLabel.stringValue = elapsed == "now" ? "Updated just now" : "Updated \(elapsed) ago"
    }

    @objc private func refresh() {
        onRefresh()
    }
}
