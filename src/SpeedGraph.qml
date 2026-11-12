import QtQuick

// Download as a filled area in the accent, upload as a dashed line, scaled to
// the peak of what is on screen so quiet periods still show their shape.
Canvas {
    id: graph

    property var points: []        // [[down, up], ...] in kbit/s
    property int capacity: 120
    property color accent: "#FFD60A"
    property color foreground: "#e6e6e6"
    property real peak: 1000

    onPointsChanged: requestPaint()
    onAccentChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const pts = points || [], n = pts.length
        let top = 1000
        for (let k = 0; k < n; k++) top = Math.max(top, pts[k][0], pts[k][1])
        peak = top * 1.15

        // Faint guide lines at a quarter, half and three quarters.
        ctx.strokeStyle = Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)
        ctx.lineWidth = 1
        for (let g = 1; g < 4; g++) {
            const gy = Math.round(height * g / 4) + 0.5
            ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
        }
        if (n < 2) return

        const step = width / (capacity - 1)
        const x0 = width - (n - 1) * step
        const y = v => height - 2 - (height - 6) * v / peak

        ctx.beginPath()
        ctx.moveTo(x0, height)
        for (let i = 0; i < n; i++) ctx.lineTo(x0 + i * step, y(pts[i][0]))
        ctx.lineTo(width, height)
        ctx.closePath()
        const fill = ctx.createLinearGradient(0, 0, 0, height)
        fill.addColorStop(0, Qt.rgba(accent.r, accent.g, accent.b, 0.35))
        fill.addColorStop(1, Qt.rgba(accent.r, accent.g, accent.b, 0.02))
        ctx.fillStyle = fill
        ctx.fill()

        ctx.beginPath()
        for (let j = 0; j < n; j++) {
            if (j === 0) ctx.moveTo(x0, y(pts[0][0])); else ctx.lineTo(x0 + j * step, y(pts[j][0]))
        }
        ctx.strokeStyle = accent
        ctx.lineWidth = 2
        ctx.stroke()

        ctx.beginPath()
        for (let u = 0; u < n; u++) {
            if (u === 0) ctx.moveTo(x0, y(pts[0][1])); else ctx.lineTo(x0 + u * step, y(pts[u][1]))
        }
        ctx.strokeStyle = Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
        ctx.setLineDash([4, 4])
        ctx.lineWidth = 1.25
        ctx.stroke()
    }
}
