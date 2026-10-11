import Foundation

public struct FigureInputError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

struct FieldKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

func inputPath(_ keys: [any CodingKey]) -> String {
    keys.reduce("") { path, key in
        if let index = key.intValue { return path + "[\(index)]" }
        return path.isEmpty ? key.stringValue : path + "." + key.stringValue
    }
}

struct Fields {
    let container: KeyedDecodingContainer<FieldKey>
    let path: String

    init(_ decoder: any Decoder, _ allowed: String) throws {
        container = try decoder.container(keyedBy: FieldKey.self)
        path = inputPath(decoder.codingPath)
        let keys = Set(allowed.split(separator: " ").map(String.init))
        if let key = container.allKeys.sorted(by: { $0.stringValue < $1.stringValue })
            .first(where: { !keys.contains($0.stringValue) }) {
            throw FigureInputError("\(field(key.stringValue)): unknown field (allowed: \(allowed))")
        }
    }

    func field(_ name: String) -> String { path.isEmpty ? name : "\(path).\(name)" }
    func value<T: Decodable>(_ name: String, _ fallback: T) throws -> T {
        guard container.contains(FieldKey(name)) else { return fallback }
        return try required(name)
    }
    func optional<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T? {
        do { return try container.decodeIfPresent(type, forKey: FieldKey(name)) }
        catch { throw FigureInputError("\(field(name)): invalid \(T.self)") }
    }
    func required<T: Decodable>(_ name: String) throws -> T {
        do { return try container.decode(T.self, forKey: FieldKey(name)) }
        catch let error as FigureInputError { throw error }
        catch { throw FigureInputError("\(field(name)): expected \(T.self)") }
    }
    func number(_ name: String, _ fallback: Double, _ range: ClosedRange<Double>) throws -> Double {
        let result: Double = try value(name, fallback)
        guard result.isFinite, range.contains(result) else {
            throw FigureInputError("\(field(name)): expected \(range.lowerBound)...\(range.upperBound)")
        }
        return result
    }
    func integer(_ name: String, _ fallback: Int, _ range: ClosedRange<Int>) throws -> Int {
        let result: Int = try value(name, fallback)
        guard range.contains(result) else {
            throw FigureInputError("\(field(name)): expected \(range.lowerBound)...\(range.upperBound)")
        }
        return result
    }
    func choice(_ name: String, _ fallback: String, _ options: String) throws -> String {
        let result: String = try value(name, fallback)
        guard options.split(separator: " ").contains(Substring(result)) else {
            throw FigureInputError("\(field(name)): expected one of \(options)")
        }
        return result
    }
    func color(_ name: String, _ fallback: String) throws -> String {
        let result: String = try value(name, fallback)
        try Self.checkColor(result, field(name))
        return result
    }
    static func checkColor(_ value: String, _ field: String) throws {
        guard value.first == "#", [4, 5, 7, 9].contains(value.count),
              value.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw FigureInputError("\(field): expected a hex color (#RGB, #RGBA, #RRGGBB or #RRGGBBAA)")
        }
    }
}
