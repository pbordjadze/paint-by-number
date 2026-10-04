/// Output of the segmentation stage: every pixel belongs to exactly one region, and
/// every region has exactly one palette color.
public struct Segmentation: Sendable {
    /// Region index per pixel, `0..<regionColor.count`. Regions are 4-connected.
    public var labels: RegionMap
    /// Palette index per region.
    public var regionColor: [UInt32]
    public var palette: [PaletteColor]
    public var colorSpace: RGBColorSpace

    public init(labels: RegionMap, regionColor: [UInt32], palette: [PaletteColor], colorSpace: RGBColorSpace) {
        self.labels = labels
        self.regionColor = regionColor
        self.palette = palette
        self.colorSpace = colorSpace
    }

    public var width: Int { labels.width }
    public var height: Int { labels.height }
    public var regionCount: Int { regionColor.count }
}
