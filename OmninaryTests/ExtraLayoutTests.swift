import SwiftUI
import Testing
@testable import Omninary

struct ExtraLayoutTests {
    @MainActor
    @Test(arguments: [320.0, 375.0, 414.0, 430.0, 768.0])
    func backdropDoesNotExpandPhoneLayout(width: Double) throws {
        // Mirrors the root composition that previously let decorative circles
        // push the entire Extra interface beyond the phone's available width.
        let view = ZStack {
            AuroraBackdrop()
            Color.clear
        }
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: width, height: 896)
        renderer.scale = 1
        let image = try #require(renderer.uiImage)
        #expect(abs(image.size.width - width) < 1)
        #expect(abs(image.size.height - 896) < 1)
    }
}
