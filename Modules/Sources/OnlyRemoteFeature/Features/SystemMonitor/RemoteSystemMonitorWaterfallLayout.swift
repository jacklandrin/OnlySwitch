import RemoteCore
import SwiftUI
import UIKit

struct RemoteSystemMonitorWaterfallLayout: Layout {
    enum DeviceClass: Equatable, Sendable {
        case phone
        case iPadMini
        case iPad

        static func classify(
            userInterfaceIdiom: UIUserInterfaceIdiom,
            containerSize: CGSize
        ) -> Self {
            guard userInterfaceIdiom == .pad else { return .phone }
            return min(containerSize.width, containerSize.height) <= 744
                ? .iPadMini
                : .iPad
        }
    }

    struct Placement: Equatable {
        let metric: SystemMonitorMetric
        let column: Int
        let origin: CGPoint
        let size: CGSize
    }

    static let spacing: CGFloat = 16
    static let minimumCardWidth: CGFloat = 220

    let columnCount: Int
    let spacing: CGFloat

    init(columnCount: Int, spacing: CGFloat = Self.spacing) {
        self.columnCount = max(1, columnCount)
        self.spacing = spacing
    }

    static func columnCount(
        containerWidth: CGFloat,
        deviceClass: DeviceClass,
        dynamicTypeSize: DynamicTypeSize
    ) -> Int {
        guard dynamicTypeSize.isAccessibilitySize == false else { return 1 }

        let fittedColumns = max(
            1,
            Int((containerWidth + spacing) / (minimumCardWidth + spacing))
        )
        let maximumColumns = switch deviceClass {
        case .phone: 2
        case .iPadMini: 2
        case .iPad: 3
        }
        return min(maximumColumns, fittedColumns)
    }

    static func placements(
        metrics: [SystemMonitorMetric],
        sizes: [CGSize],
        columnCount: Int,
        columnWidth: CGFloat,
        spacing: CGFloat = Self.spacing
    ) -> [Placement] {
        zip(metrics, placementGeometry(
            sizes: sizes,
            columnCount: columnCount,
            columnWidth: columnWidth,
            spacing: spacing
        )).map { metric, geometry in
            Placement(
                metric: metric,
                column: geometry.column,
                origin: geometry.origin,
                size: geometry.size
            )
        }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? idealWidth
        let geometry = layoutGeometry(width: width, subviews: subviews)
        return CGSize(width: width, height: geometry.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let geometry = layoutGeometry(width: bounds.width, subviews: subviews)
        for (subview, placement) in zip(subviews, geometry.placements) {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + placement.origin.x,
                    y: bounds.minY + placement.origin.y
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private var idealWidth: CGFloat {
        CGFloat(columnCount) * Self.minimumCardWidth
            + CGFloat(columnCount - 1) * spacing
    }

    private func layoutGeometry(width: CGFloat, subviews: Subviews) -> LayoutGeometry {
        let columnWidth = max(
            0,
            (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        )
        let sizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
        }
        let placements = Self.placementGeometry(
            sizes: sizes,
            columnCount: columnCount,
            columnWidth: columnWidth,
            spacing: spacing
        )
        let height = placements.map { $0.origin.y + $0.size.height }.max() ?? 0
        return LayoutGeometry(placements: placements, height: height)
    }

    private static func placementGeometry(
        sizes: [CGSize],
        columnCount: Int,
        columnWidth: CGFloat,
        spacing: CGFloat
    ) -> [GeometryPlacement] {
        guard columnCount > 0 else { return [] }

        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)
        return sizes.map { measuredSize in
            var shortestColumn = 0
            for column in columnHeights.indices.dropFirst()
            where columnHeights[column] < columnHeights[shortestColumn] {
                shortestColumn = column
            }

            let size = CGSize(width: columnWidth, height: measuredSize.height)
            let placement = GeometryPlacement(
                column: shortestColumn,
                origin: CGPoint(
                    x: CGFloat(shortestColumn) * (columnWidth + spacing),
                    y: columnHeights[shortestColumn]
                ),
                size: size
            )
            columnHeights[shortestColumn] += size.height + spacing
            return placement
        }
    }

    private struct GeometryPlacement {
        let column: Int
        let origin: CGPoint
        let size: CGSize
    }

    private struct LayoutGeometry {
        let placements: [GeometryPlacement]
        let height: CGFloat
    }
}
