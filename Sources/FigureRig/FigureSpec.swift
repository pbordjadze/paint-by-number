import Foundation

/// Version 1 taste parameters. Each nested decoder rejects unknown keys and validates the
/// ranges in factory/SPEC.md; omitted fields use the table's defaults, without normalization.
public struct FigureSpec: Codable, Sendable {
    public var version = 1
    public var figure = Figure()
    public var ink = Ink()
    public var motion = Motion()
    public var magic = Magic()
    public var view = View()
    public var card = Card()
    public init() {}
    public init(from decoder: any Decoder) throws {
        let d = try Fields(decoder, "version figure ink motion magic view card")
        version = try d.integer("version", 1, 1...1)
        figure = try d.value("figure", Figure()); ink = try d.value("ink", Ink())
        motion = try d.value("motion", Motion()); magic = try d.value("magic", Magic())
        view = try d.value("view", View()); card = try d.value("card", Card())
    }

    /// Ground to the crown of the standing rig, before projection. The ink and clothing
    /// surround this skeleton; neither changes the gait's units.
    public var normalizationScale: Double {
        1 / (0.97 * (figure.thigh + figure.shin) + figure.torso + figure.neck + figure.headSize)
    }

    public struct Figure: Codable, Sendable {
        public var headSize = 0.16, headAspect = 0.85, neck = 0.03, torso = 0.30, hunch = 0.10
        public var shoulderWidth = 0.12, hipWidth = 0.07, upperArm = 0.17, forearm = 0.16
        public var thigh = 0.23, shin = 0.23, foot = 0.05, knobs = 0.0
        public var hands = "dot", headwear = "kerchief", headwearSize = 1.0, knot = 0.5, skirt = 0.0
        public var accent: String?
        public init() {}
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "headSize headAspect neck torso hunch shoulderWidth hipWidth upperArm forearm thigh shin foot knobs hands headwear headwearSize knot skirt accent")
            headSize = try d.number("headSize", headSize, 0.10...0.26)
            headAspect = try d.number("headAspect", headAspect, 0.6...1.2)
            neck = try d.number("neck", neck, 0...0.08); torso = try d.number("torso", torso, 0.18...0.42)
            hunch = try d.number("hunch", hunch, 0...0.6)
            shoulderWidth = try d.number("shoulderWidth", shoulderWidth, 0...0.25)
            hipWidth = try d.number("hipWidth", hipWidth, 0...0.2)
            upperArm = try d.number("upperArm", upperArm, 0.10...0.30)
            forearm = try d.number("forearm", forearm, 0.10...0.30)
            thigh = try d.number("thigh", thigh, 0.12...0.32); shin = try d.number("shin", shin, 0.12...0.32)
            foot = try d.number("foot", foot, 0...0.10); knobs = try d.number("knobs", knobs, 0...1)
            hands = try d.choice("hands", hands, "none dot mitten")
            headwear = try d.choice("headwear", headwear, "none kerchief hood")
            headwearSize = try d.number("headwearSize", headwearSize, 0.6...1.6)
            knot = try d.number("knot", knot, 0...1); skirt = try d.number("skirt", skirt, 0...0.5)
            accent = try d.optional("accent")
            if let accent { try Fields.checkColor(accent, d.field("accent")) }
        }
    }
    public struct Ink: Codable, Sendable {
        public var color = "#2B2622", width = 0.035, taper = 0.5, pressure = 0.2, wobble = 0.006
        public var wobbleLength = 0.12, boilFps = 8.0, overshoot = 0.0
        public init() {}
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "color width taper pressure wobble wobbleLength boilFps overshoot")
            color = try d.color("color", color); width = try d.number("width", width, 0.01...0.08)
            taper = try d.number("taper", taper, 0...1); pressure = try d.number("pressure", pressure, 0...1)
            wobble = try d.number("wobble", wobble, 0...0.03)
            wobbleLength = try d.number("wobbleLength", wobbleLength, 0.03...0.5)
            boilFps = try d.number("boilFps", boilFps, 0...24); overshoot = try d.number("overshoot", overshoot, 0...0.05)
        }
    }
    public struct Motion: Codable, Sendable {
        public var fps = 24, onTwos = true, step = 0.26, cadence = 2.0, bounce = 0.03, sway = 0.01
        public var lean = 4.0, armSwing = 25.0, footLift = 0.05, ease = 0.5, turnRate = 360.0
        public var headingSteps = 0, anticipation = 0.25, followThrough = 0.15, settle = 0.3
        public init() {}
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "fps onTwos step cadence bounce sway lean armSwing footLift ease turnRate headingSteps anticipation followThrough settle")
            fps = try d.integer("fps", fps, 12...60); onTwos = try d.value("onTwos", onTwos)
            step = try d.number("step", step, 0.08...0.4); cadence = try d.number("cadence", cadence, 0.8...3.5)
            bounce = try d.number("bounce", bounce, 0...0.08); sway = try d.number("sway", sway, 0...0.04)
            lean = try d.number("lean", lean, -5...20); armSwing = try d.number("armSwing", armSwing, 0...60)
            footLift = try d.number("footLift", footLift, 0.01...0.15); ease = try d.number("ease", ease, 0...1)
            turnRate = try d.number("turnRate", turnRate, 90...1080)
            headingSteps = try d.integer("headingSteps", headingSteps, 0...16)
            guard [0, 8, 16].contains(headingSteps) else { throw FigureInputError("\(d.field("headingSteps")): expected 0, 8 or 16") }
            anticipation = try d.number("anticipation", anticipation, 0...0.5)
            followThrough = try d.number("followThrough", followThrough, 0...0.4)
            settle = try d.number("settle", settle, 0.1...1)
        }
    }
    public struct Magic: Codable, Sendable {
        public var colors = ["#C9A227", "#6E9A5B"], shape = "sparkle", size = 0.07, trail = 4.0, burst = 24
        public var life = 1.2, drift = 0.25, spread = 0.6, twinkle = 3.0, glow = 0.0
        public init() {}
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "colors shape size trail burst life drift spread twinkle glow")
            colors = try d.value("colors", colors)
            guard (1...4).contains(colors.count) else { throw FigureInputError("\(d.field("colors")): expected 1...4 hex colors") }
            for (i, color) in colors.enumerated() { try Fields.checkColor(color, "\(d.field("colors"))[\(i)]") }
            shape = try d.choice("shape", shape, "sparkle dot leaf star")
            size = try d.number("size", size, 0.01...0.1); trail = try d.number("trail", trail, 0...20)
            burst = try d.integer("burst", burst, 0...80); life = try d.number("life", life, 0.3...3)
            drift = try d.number("drift", drift, 0...1); spread = try d.number("spread", spread, 0...2)
            twinkle = try d.number("twinkle", twinkle, 0...8); glow = try d.number("glow", glow, 0...1)
        }
    }
    public struct View: Codable, Sendable {
        public var depth = 0.5, heightScale = 1.0
        public init() {}
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "depth heightScale")
            depth = try d.number("depth", depth, 0...1); heightScale = try d.number("heightScale", heightScale, 0.7...1.2)
        }
    }
    public struct Card: Codable, Sendable {
        public var size = 15.0, position = "bottomLeading", backdrop = "none", fade = 0.3, holdBase = 0.5, perWord = 0.2
        public init() {}
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "size position backdrop fade holdBase perWord")
            size = try d.number("size", size, 11...22)
            position = try d.choice("position", position, "top bottom topLeading bottomLeading")
            backdrop = try d.choice("backdrop", backdrop, "none paper")
            fade = try d.number("fade", fade, 0.1...0.8); holdBase = try d.number("holdBase", holdBase, 0.3...1.5)
            perWord = try d.number("perWord", perWord, 0.12...0.35)
        }
    }
}
