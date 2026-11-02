#if DEBUG
import UIKit

/// `-IslandRenderDump` writes the home island and sample stages as PNGs into Documents, for comparing with the demo.
enum IslandDebugDump {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-IslandRenderDump") else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        func save(_ name: String, _ canvas: PixelCanvas) {
            guard let cg = canvas.makeImage(), let data = UIImage(cgImage: cg).pngData() else { return }
            try? data.write(to: dir.appendingPathComponent(name + ".png"))
        }
        var t = Date()
        func lap(_ s: String) { print("[IslandDump] \(s): \(Int(Date().timeIntervalSince(t) * 1000)) ms"); t = Date() }
        let state = IslandLayout(openRegions: ["A", "C"], buildings: IslandMaps.starterBuildings)
        let home = IslandMaps.buildHome(state); lap("buildHome")
        _ = home.map.fields; lap("fields")
        save("home", IslandPaint.still(home.map)); lap("paint home")
        save("forest3", IslandPaint.still(IslandMaps.genStage("forest", 3)))
        save("lake2", IslandPaint.still(IslandMaps.genStage("lake", 2)))
        save("city1", IslandPaint.still(IslandMaps.genCity(1)))
        save("desert4", IslandPaint.still(IslandMaps.genDesert(4))); lap("stages")
        print("[IslandDump] saved to \(dir.path)")
    }
}
#endif
