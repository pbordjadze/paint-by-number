import Foundation
import Messages
import UIKit

/// Paint by Moonlight's stickers in Messages (painting-company row 349): the finished paintings
/// as the app made stickers of them (`OutsideShelf.Stickers`; the app's `StickerMaker`). The
/// extension reads the shelf's pictures and nothing else; Messages sends the one picked.
final class MessagesViewController: MSMessagesAppViewController {
    private let browser = StickerBrowser(stickerSize: .regular)
    private let empty = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(browser)
        browser.view.frame = view.bounds
        browser.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(browser.view)
        browser.didMove(toParent: self)

        empty.text = String(localized: "Finish a painting in Paint by Moonlight and its stickers appear here.")
        empty.font = .preferredFont(forTextStyle: .callout)
        empty.adjustsFontForContentSizeCategory = true
        empty.textColor = .secondaryLabel
        empty.textAlignment = .center
        empty.numberOfLines = 0
        empty.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 16),
            empty.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -16),
        ])
        reload()
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        reload()
    }

    /// Reads the shelf again: the app may have laid out new stickers since Messages last showed these.
    private func reload() {
        browser.stickers = Self.stickers(on: OutsideShelf.shared())
        browser.stickerBrowserView.reloadData()
        empty.isHidden = !browser.stickers.isEmpty
        browser.view.isHidden = browser.stickers.isEmpty
    }

    /// The shelf's stickers whose pictures are there and Messages takes.
    static func stickers(on shelf: OutsideShelf?) -> [MSSticker] {
        guard let shelf, let list = shelf.stickers() else { return [] }
        return list.stickers.compactMap { sticker in
            try? MSSticker(contentsOfFileURL: shelf.url(sticker.picture), localizedDescription: sticker.title)
        }
    }
}

/// The browser, its own data source: the stickers in the shelf's order.
final class StickerBrowser: MSStickerBrowserViewController {
    var stickers: [MSSticker] = []

    override func numberOfStickers(in stickerBrowserView: MSStickerBrowserView) -> Int { stickers.count }

    override func stickerBrowserView(_ stickerBrowserView: MSStickerBrowserView, stickerAt index: Int) -> MSSticker {
        stickers[index]
    }
}
