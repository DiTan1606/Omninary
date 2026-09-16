import UIKit

@MainActor
enum AppIconManager {
    static let extraordinaryIconName = "ExtraordinaryAppIcon"

    static func synchronize(hasExtraordinaryAccess: Bool) async {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        let requestedIconName = hasExtraordinaryAccess ? extraordinaryIconName : nil
        guard UIApplication.shared.alternateIconName != requestedIconName else { return }

        do {
            try await UIApplication.shared.setAlternateIconName(requestedIconName)
        } catch {
            print("Không thể đổi biểu tượng ứng dụng: \(error.localizedDescription)")
        }
    }
}
