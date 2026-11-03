//
//  PullMenuTitle.swift
//  pullBar
//

import AppKit

enum CheckState {
    case success, failure, pending, neutral

    /// Maps a check run conclusion or status context state. `nil` means the check is still running.
    init(conclusion: String?) {
        switch conclusion {
        case "SUCCESS":
            self = .success
        case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ERROR":
            self = .failure
        case nil, "", "PENDING", "EXPECTED", "ACTION_REQUIRED":
            self = .pending
        default:
            self = .neutral
        }
    }
}

/// Builds the attributed titles for pull request rows and category headers in the status bar menu.
enum PullMenuTitle {

    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let detailFont = NSFont.systemFont(ofSize: 11)

    private static let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let green = NSColor(named: "green") ?? .systemGreen
    private static let red = NSColor(named: "red") ?? .systemRed
    private static let yellow = NSColor(named: "yellow") ?? .systemYellow

    /// Title row, then repository, author, age, approvals, diff size and checks, then labels when `showLabels` is set.
    /// The first line ends at the first newline, which the Copy Link alternate relies on.
    static func title(for pull: Edge, checks: [CheckState], showLabels: Bool) -> NSAttributedString {
        let node = pull.node
        let title = NSMutableAttributedString()

        if !node.isReadByViewer {
            title.appendString(string: "● ", color: .systemBlue, font: detailFont)
        }
        title
            .appendString(string: node.title.trunc(length: 50), color: node.isDraft ? .secondaryLabelColor : .labelColor, font: titleFont)
            .appendString(string: "  #\(node.number)", color: .secondaryLabelColor, font: digitsFont)
        if node.isDraft {
            title
                .appendString(string: "  ", color: .clear, font: detailFont)
                .appendPill(text: "Draft", color: .secondaryLabelColor, lineFont: titleFont)
        }

        let approvals = node.reviews.totalCount
        let approvedByMe = node.reviews.edges.contains { $0.node.viewerDidAuthor }
        title
            .appendNewLine()
            .appendIcon(iconName: "repo")
            .appendString(string: node.repository.name, color: .secondaryLabelColor, font: detailFont)
            .appendDetailSeparator()
            .appendIcon(iconName: "person")
            .appendString(string: node.author?.login ?? User.ghost.login, color: .secondaryLabelColor, font: detailFont)
            .appendDetailSeparator()
            .appendIcon(iconName: "calendar")
            .appendString(string: node.createdAt.getElapsedInterval(), color: .secondaryLabelColor, font: digitsFont)
            .appendDetailSeparator()
        if approvals > 0 {
            title.appendPill(
                text: String(approvals),
                symbol: approvedByMe ? "checkmark.circle.fill" : "checkmark",
                color: green,
                lineFont: detailFont
            )
        } else {
            title.appendString(string: "✓ 0", color: .tertiaryLabelColor, font: digitsFont)
        }
        title
            .appendString(string: "   ", color: .clear, font: detailFont)
            .appendString(string: "+\(node.additions ?? 0)", color: green.readable, font: digitsFont)
            .appendString(string: " −\(node.deletions ?? 0)", color: red.readable, font: digitsFont)

        if let summary = checksSummary(checks) {
            title
                .appendString(string: "   ", color: .clear, font: detailFont)
                .appendPill(text: summary.text, symbol: summary.symbol, color: summary.color, lineFont: detailFont)
        }

        if showLabels && !node.labels.nodes.isEmpty {
            title.appendNewLine()
            for label in node.labels.nodes {
                title
                    .appendPill(text: label.name, color: hexColor(hex: label.color), lineFont: detailFont)
                    .appendString(string: " ", color: .clear, font: detailFont)
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
        return title
    }

    static func sectionHeader(name: String, count: Int) -> NSAttributedString {
        NSMutableAttributedString()
            .appendString(string: name.uppercased(), color: .secondaryLabelColor, font: .systemFont(ofSize: 11, weight: .semibold), kern: 0.6)
            .appendString(string: "  ", color: .clear, font: detailFont)
            .appendPill(text: String(count), color: .secondaryLabelColor, lineFont: detailFont)
    }

    /// Passed over relevant checks, coloured by the worst state. Skipped, neutral and cancelled runs are left out.
    private static func checksSummary(_ checks: [CheckState]) -> (text: String, symbol: String, color: NSColor)? {
        let relevant = checks.filter { $0 != .neutral }
        guard !relevant.isEmpty else { return nil }

        let text = "\(relevant.filter { $0 == .success }.count)/\(relevant.count)"
        if relevant.contains(.failure) {
            return (text, "xmark", red)
        } else if relevant.contains(.pending) {
            return (text, "clock", yellow)
        } else {
            return (text, "checkmark", green)
        }
    }
}

private extension NSMutableAttributedString {
    @discardableResult
    func appendDetailSeparator() -> NSMutableAttributedString {
        appendString(string: "  ·  ", color: .tertiaryLabelColor, font: PullMenuTitle.detailFont)
    }
}
