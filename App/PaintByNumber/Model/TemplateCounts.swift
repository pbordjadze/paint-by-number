import Foundation

/// How many colors and areas a template has, worded for the create flow's summary and the
/// printable template's header and color key.
nonisolated enum TemplateCounts {
    static func colors(_ count: Int) -> String {
        String(localized: "template.colors", defaultValue: "\(count) colors",
               comment: "How many colors a template has; the argument is the count")
    }

    static func areas(_ count: Int) -> String {
        String(localized: "template.areas", defaultValue: "\(count) areas",
               comment: "How many areas (regions to paint) a template has; the argument is the count")
    }
}
