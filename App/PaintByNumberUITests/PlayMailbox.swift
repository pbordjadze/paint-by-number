#if DEBUG
import CoreFoundation
import Foundation

/// Version 1 wire objects. Keep validation strict, including nested point objects and JSON
/// booleans (Foundation bridges them to NSNumber, just like numbers).
enum PlayMove {
    case fill(Int), tap(String), drag(PlayPoint, PlayPoint, steps: Int), wait(Double), screenshot

    init(data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let fields = object as? [String: Any], let action = fields["do"] as? String else {
            throw PlayFailure("Move must be an object with a string do field")
        }
        switch action {
        case "fill":
            try PlayWire.keys(fields, ["do", "area"])
            self = .fill(try PlayWire.integer(fields["area"], minimum: 1, name: "area"))
        case "tap":
            try PlayWire.keys(fields, ["do", "label"])
            guard let label = fields["label"] as? String,
                  !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PlayFailure("label must be a nonempty string")
            }
            self = .tap(label)
        case "drag":
            try PlayWire.keys(fields, ["do", "from", "to", "steps"])
            self = .drag(
                try PlayPoint(fields["from"]), try PlayPoint(fields["to"]),
                steps: try PlayWire.integer(fields["steps"], minimum: 1, name: "steps"))
        case "wait":
            try PlayWire.keys(fields, ["do", "seconds"])
            self = .wait(try PlayWire.number(fields["seconds"], name: "seconds"))
        case "screenshot":
            try PlayWire.keys(fields, ["do"])
            self = .screenshot
        default: throw PlayFailure("Unknown move: \(action)")
        }
    }
}

struct PlayPoint: Sendable {
    let x: Double
    let y: Double

    init(_ object: Any?) throws {
        guard let fields = object as? [String: Any] else { throw PlayFailure("Point must be an object") }
        try PlayWire.keys(fields, ["x", "y"])
        x = try PlayWire.number(fields["x"], name: "x")
        y = try PlayWire.number(fields["y"], name: "y")
    }
}

struct PlayState: Equatable, Sendable {
    let screen: String
    let selectedPaint: Int?
    let filledAreas: [Int]
    let areaCount: Int

    init(data: Data) throws {
        guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlayFailure("State must be an object")
        }
        try PlayWire.keys(fields, ["screen", "selected_paint", "filled_areas", "area_count"])
        guard let screen = fields["screen"] as? String,
              !screen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let filled = fields["filled_areas"] as? [Any] else { throw PlayFailure("Invalid state") }
        self.screen = screen
        areaCount = try PlayWire.integer(fields["area_count"], minimum: 0, name: "area_count")
        selectedPaint = fields["selected_paint"] is NSNull ? nil
            : try PlayWire.integer(fields["selected_paint"], minimum: 1, name: "selected_paint")
        filledAreas = try filled.map { try PlayWire.integer($0, minimum: 1, name: "filled area") }
        guard Set(filledAreas).count == filledAreas.count, filledAreas.allSatisfy({ $0 <= areaCount }) else {
            throw PlayFailure("Filled areas must be unique and within area_count")
        }
    }

    var object: [String: Any] {
        ["screen": screen, "selected_paint": selectedPaint as Any? ?? NSNull(),
         "filled_areas": filledAreas, "area_count": areaCount]
    }
}

struct PlayFailure: Error, CustomStringConvertible {
    let description: String
    init(_ reason: String) { description = reason }
}

enum PlayWire {
    static func keys(_ fields: [String: Any], _ expected: Set<String>) throws {
        guard Set(fields.keys) == expected else {
            throw PlayFailure("Expected exactly these fields: \(expected.sorted().joined(separator: ", "))")
        }
    }

    static func number(_ value: Any?, name: String) throws -> Double {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue >= 0 else {
            throw PlayFailure("\(name) must be a finite nonnegative number")
        }
        return value.doubleValue
    }

    static func integer(_ value: Any?, minimum: Int, name: String) throws -> Int {
        let number = try number(value, name: name)
        // The factory distinguishes JSON ints from floats, even 1.0 or 1e0. Preserve that
        // distinction and avoid rounding a large integer through Double before conversion.
        guard let boxed = value as? NSNumber, !["f", "d"].contains(String(cString: boxed.objCType)),
              number >= Double(minimum), let integer = Int(boxed.stringValue), integer >= minimum else {
            throw PlayFailure("\(name) must be an integer >= \(minimum)")
        }
        return integer
    }

    /// moveItem renames within this directory. Refuse existing destinations: every published
    /// JSON file is part of the wire log, including errors and the self-test's moves.
    static func publish(_ object: [String: Any], named name: String, in mailbox: URL) throws {
        let temporary = mailbox.appending(path: ".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try JSONSerialization.data(withJSONObject: object, options: .sortedKeys).write(to: temporary)
        try FileManager.default.moveItem(at: temporary, to: mailbox.appending(path: name))
    }
}
#endif
