/// Locale-independent fixed precision, including a canonical representation of zero.
func svgNumber(_ value: Double) -> String {
    let scaled = Int64((value * 100).rounded())
    let magnitude = scaled.magnitude
    let fraction = magnitude % 100
    return (scaled < 0 ? "-" : "") + String(magnitude / 100) + "." + (fraction < 10 ? "0" : "") + String(fraction)
}
func xmlEscape(_ value: String) -> String {
    var output = ""
    for c in value {
        switch c { case "&": output += "&amp;"; case "<": output += "&lt;"; case ">": output += "&gt;"; case "\"": output += "&quot;"; case "'": output += "&apos;"; default: output.append(c) }
    }
    return output
}
public enum FigureSVG {
    public static func write(_ frame: FigureFrame, scene: FigureScene, background: String? = nil) -> String {
        let w = svgNumber(scene.canvas.width), h = svgNumber(scene.canvas.height)
        var output = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">\n"
        let blurred = frame.shapes.enumerated().filter { $0.element.blur != nil }
        if !blurred.isEmpty {
            output += "<defs>\n"
            for (i, shape) in blurred {
                output += "<filter id=\"blur\(i)\" x=\"-100%\" y=\"-100%\" width=\"300%\" height=\"300%\"><feGaussianBlur stdDeviation=\"\(svgNumber(shape.blur!))\"/></filter>\n"
            }
            output += "</defs>\n"
        }
        output += "<rect data-layer=\"background\" width=\"\(w)\" height=\"\(h)\" fill=\"\(scene.canvas.paper)\"/>\n"
        if let background = background ?? scene.background {
            output += "<image data-layer=\"background\" href=\"\(xmlEscape(background))\" width=\"\(w)\" height=\"\(h)\" preserveAspectRatio=\"none\"/>\n"
        }
        for (i, shape) in frame.shapes.enumerated() {
            var path = ""
            for points in shape.subpaths where !points.isEmpty {
                path += "M\(svgNumber(points[0].x)),\(svgNumber(points[0].y))"
                for p in points.dropFirst() { path += "L\(svgNumber(p.x)),\(svgNumber(p.y))" }
                path += "Z"
            }
            output += "<path data-layer=\"\(shape.layer)\" d=\"\(path)\" fill=\"\(shape.color)\" fill-rule=\"evenodd\" opacity=\"\(svgNumber(shape.opacity))\""
            if shape.blur != nil { output += " filter=\"url(#blur\(i))\"" }
            output += "/>\n"
        }
        return output + "</svg>\n"
    }
}
