import CoreGraphics

/// Window frames for the slide animation, in screen coordinates (origin bottom-left).
public enum WindowGeometry {
    /// Frame when fully shown: full display width, `heightRatio` of the usable height,
    /// docked under the menu bar (top) or above the Dock (bottom).
    public static func shownFrame(screen: CGRect, visible: CGRect, edge: SlideEdge, heightRatio: Double) -> CGRect {
        let height = (visible.height * clamp(heightRatio, Constants.heightRatioRange)).rounded()
        let y =
            switch edge {
            case .top: visible.maxY - height
            case .bottom: visible.minY
            }
        return CGRect(x: screen.minX, y: y, width: screen.width, height: height)
    }

    /// Frame the window slides from / to: just past the physical screen edge, so no part of it
    /// shows through the menu bar or the Dock while it moves.
    public static func hiddenFrame(shown: CGRect, screen: CGRect, edge: SlideEdge) -> CGRect {
        var frame = shown
        frame.origin.y =
            switch edge {
            case .top: screen.maxY
            case .bottom: screen.minY - shown.height
            }
        return frame
    }

    /// Steps the grow (+1) and shrink (-1) keys apply for `edge`. Sliding from the bottom swaps them,
    /// so a key keeps moving the free edge the same way on screen whichever edge the window uses.
    public static func resizeSteps(_ steps: Int, edge: SlideEdge) -> Int {
        switch edge {
        case .top: steps
        case .bottom: -steps
        }
    }

    /// Height ratio after one press of the grow (+1) or shrink (-1) key.
    public static func resizedRatio(_ ratio: Double, steps: Int) -> Double {
        clamp(ratio + Double(steps) * Constants.resizeStep, Constants.heightRatioRange)
    }
}
