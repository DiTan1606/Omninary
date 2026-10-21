import UIKit

@MainActor
enum AppIconManager {
    static let extraordinaryDefaultIconName = "OmniExtraordinaryAppIcon"
    static let ditandnaryIconId = "ditandnary_classic"
    static let extraordinaryIconId = "extraordinary_aurora"
    static let chronoIconId = "omni_mythic_imperial_chrono"
    static let chronoAppIconName = "OmniMythicImperialChronoAppIcon"
    static let solarIconId = "omni_mythic_solar_system"
    static let solarAppIconName = "OmniMythicSolarSystemAppIcon"
    private static var isChangingIcon = false

    // Tên biểu tượng là tài nguyên đóng gói cùng ứng dụng, không lấy tên tùy ý từ máy chủ.
    // Máy chủ chỉ quyết định Omnicon nào được hiển thị và mở khóa.
    static let bundledIconNamesById: [String: String] = [
        extraordinaryIconId: extraordinaryDefaultIconName,
        "omni_aisc_26": "OmniAISC26AppIcon",
        "omni_streak_30": "OmniStreak30AppIcon",
        "omni_streak_100": "OmniStreak100AppIcon",
        "omni_streak_200": "OmniStreak200AppIcon",
        "omni_streak_300": "OmniStreak300AppIcon",
        "omni_season_spring": "OmniSeasonSpringAppIcon",
        "omni_season_summer": "OmniSeasonSummerAppIcon",
        "omni_season_autumn": "OmniSeasonAutumnAppIcon",
        "omni_season_winter": "OmniSeasonWinterAppIcon",
        "omni_legendary_celestial_oracle": "OmniLegendaryCelestialOracleAppIcon",
        "omni_legendary_imperial_koi": "OmniLegendaryImperialKoiAppIcon",
        "omni_mythic_jade_dragon": "OmniMythicJadeDragonAppIcon",
        chronoIconId: chronoAppIconName,
        solarIconId: solarAppIconName
    ]

    enum IconError: LocalizedError {
        case unsupported
        case missingBundledIcon(String)
        case changeInProgress
        case applicationNotActive
        case systemRejected(NSError)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "Thiết bị này không hỗ trợ đổi biểu tượng ứng dụng."
            case .missingBundledIcon(let name):
                return "Biểu tượng \(name) chưa được đăng ký trong ứng dụng."
            case .changeInProgress:
                return "Ứng dụng đang đổi biểu tượng. Vui lòng thử lại sau ít giây."
            case .applicationNotActive:
                return "Ứng dụng chưa sẵn sàng hiển thị hộp thoại hệ thống. Hãy mở lại Omninary rồi thử đổi."
            case .systemRejected(let error):
                if error.domain == NSPOSIXErrorDomain, error.code == 35 {
                    return "iOS đang tạm thời từ chối đổi biểu tượng (mã lỗi 35). Lựa chọn đã được lưu trong app; hãy mở lại Omninary rồi chạm ‘Thử đổi biểu tượng ứng dụng’ để thử lại."
                }
                return "iOS chưa chấp nhận yêu cầu đổi biểu tượng (mã lỗi \(error.code))."
            }
        }
    }

    private static var registeredAlternateIconNames: Set<String> {
        let info = Bundle.main.infoDictionary ?? [:]
        let iconDictionaries = ["CFBundleIcons", "CFBundleIcons~ipad"].compactMap {
            info[$0] as? [String: Any]
        }
        return Set(iconDictionaries
            .compactMap { $0["CFBundleAlternateIcons"] as? [String: Any] }
            .flatMap { $0.keys })
    }

    static func alternateIconName(for iconId: String) -> String? {
        if iconId == ditandnaryIconId { return nil }
        if let bundledName = bundledIconNamesById[iconId] { return bundledName }
        if let catalogName = OmniIconCatalog.shared.item(for: iconId)?.alternateIconName,
           registeredAlternateIconNames.contains(catalogName) {
            return catalogName
        }
        return nil
    }

    private static func waitUntilActive() async throws {
        for _ in 0..<20 {
            if UIApplication.shared.applicationState == .active { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw IconError.applicationNotActive
    }

    static func synchronize(hasExtraordinaryAccess: Bool, equippedIconId: String? = nil) async {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard !isChangingIcon else { return }

        let currentEquippedId = equippedIconId ?? UserDefaults.standard.string(forKey: "equipped_omni_icon_id")
        let requestedIconName: String?

        if !hasExtraordinaryAccess {
            // Khi về lại Ditandnary: icon app BẮT BUỘC phải trở về icon Ditan mặc định (nil)
            requestedIconName = nil
            UserDefaults.standard.set(ditandnaryIconId, forKey: "equipped_omni_icon_id")
        } else if let currentEquippedId = currentEquippedId, currentEquippedId != ditandnaryIconId {
            guard let bundledName = alternateIconName(for: currentEquippedId) else {
                print("Không tìm thấy biểu tượng đóng gói cho Omnicon \(currentEquippedId)")
                return
            }
            requestedIconName = bundledName
        } else {
            requestedIconName = extraordinaryDefaultIconName
        }

        guard UIApplication.shared.alternateIconName != requestedIconName else { return }
        do {
            try await setAppIcon(named: requestedIconName)
        } catch {
            print("Không thể đổi biểu tượng ứng dụng: \(error.localizedDescription)")
        }
    }

    static func setAppIcon(named iconName: String?) async throws {
        guard UIApplication.shared.supportsAlternateIcons else { throw IconError.unsupported }
        if let iconName, !registeredAlternateIconNames.contains(iconName) {
            throw IconError.missingBundledIcon(iconName)
        }
        guard UIApplication.shared.alternateIconName != iconName else { return }
        guard !isChangingIcon else { throw IconError.changeInProgress }
        isChangingIcon = true
        defer { isChangingIcon = false }

        // Để giao diện đóng xong trước khi yêu cầu hệ thống hiện hộp thoại đổi biểu tượng.
        try await Task.sleep(nanoseconds: 500_000_000)

        try await waitUntilActive()
        do {
            try await UIApplication.shared.setAlternateIconName(iconName)
        } catch {
            // Giữ nguyên lỗi gốc của iOS. Token (mã phiên) hộp thoại lỗi không có nghĩa là
            // iPhone thật sự đang bận; gọi lặp hoặc gọi lại khi app quay lại màn hình có thể
            // gửi cùng một yêu cầu bị từ chối nhiều lần.
            let native = error as NSError
            print("[AppIcon] requested=\(iconName ?? "primary") iOS=\(UIDevice.current.systemVersion) error=\(native.domain)/\(native.code) details=\(native.userInfo)")
            throw IconError.systemRejected(native)
        }
    }
}
