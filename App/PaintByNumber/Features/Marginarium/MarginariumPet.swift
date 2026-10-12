import Foundation

/// Pet identifiers shared by the chapter tool and the reader. Pip and Colophon retain their
/// imagesets and timing. Each guardian's pet is one uniquely named `pet-<id>.webp` resource;
/// the chapter says `![description](pet:<id>)`, and `MarginariumSpeakers` maps a margin
/// note's signature to the id.
struct MarginariumPet {
    enum Art {
        case imagesets(SpriteAnimation)
        case atlas(URL)
    }

    let id: String
    let art: Art
    let hint: String

    static let pip = MarginariumPet(id: "pip", art: .imagesets(PipSprite.animation),
                                    hint: String(localized: "Lifts its lid."))
    static let colophon = MarginariumPet(id: "colophon", art: .imagesets(ColophonSprite.animation),
                                         hint: String(localized: "Folds its wings like a bookmark."))

    static func named(_ id: String?, bundle: Bundle = .main) -> MarginariumPet? {
        guard let id else { return nil }
        switch id {
        case "pip": return pip
        case "colophon": return colophon
        default:
            guard id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil,
                  let url = bundle.url(forResource: "pet-\(id)", withExtension: "webp") else { return nil }
            return MarginariumPet(id: id, art: .atlas(url), hint: String(localized: "Waves hello."))
        }
    }

    var animation: SpriteAnimation {
        switch art {
        case .imagesets(let animation): animation
        case .atlas: SpriteAtlas.animation
        }
    }
}
