import SwiftUI

/// Các bậc Omnicon dùng chung thang CEFR. C2 luôn hiện trong giao diện để
/// sẵn sàng cho Omnicon cấp cao nhất, kể cả khi catalog chưa có vật phẩm C2.
enum OmniCEFRLevel: String, CaseIterable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"
}

/// The Omnicon catalog is owned by Supabase. The app keeps only its last loaded presentation state.
struct OmniIconItem: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let tier: String
    let asset_name: String
    let alternate_icon_name: String?
    let subtitle: String
    let is_extra_exclusive: Bool
    let points_required: Int?
    let streak_days_required: Int?
    let rarity: String
    let category: String
    let category_sort_order: Int
    let sort_order: Int

    var assetName: String { asset_name }
    var alternateIconName: String? { alternate_icon_name }
    var isExtraExclusive: Bool { is_extra_exclusive }
    var pointsRequired: Int? { points_required }
    var streakDaysRequired: Int? { streak_days_required }
}

@MainActor
final class OmniIconCatalog: ObservableObject {
    static let shared = OmniIconCatalog()

    static let imperialChronoItem = OmniIconItem(
        id: "omni_mythic_imperial_chrono",
        name: "Cỗ Máy Thời Gian",
        tier: "C2",
        asset_name: "OmniMythicImperialChrono",
        alternate_icon_name: "OmniMythicImperialChronoAppIcon",
        subtitle: "Cỗ Máy Thời Gian Hoàng Kim Vĩnh Cửu",
        is_extra_exclusive: true,
        points_required: 1500,
        streak_days_required: nil,
        rarity: "mythic",
        category: "C2",
        category_sort_order: 6,
        sort_order: 60
    )

    static let solarSystemItem = OmniIconItem(
        id: "omni_mythic_solar_system",
        name: "Hệ Mặt Trời",
        tier: "C2",
        asset_name: "OmniMythicSolarSystem",
        alternate_icon_name: "OmniMythicSolarSystemAppIcon",
        subtitle: "Vũ Trụ Không Gian & 8 Hành Tinh",
        is_extra_exclusive: true,
        points_required: 1500,
        streak_days_required: nil,
        rarity: "mythic",
        category: "C2",
        category_sort_order: 6,
        sort_order: 61
    )

    @Published private(set) var items: [OmniIconItem] = [OmniIconCatalog.imperialChronoItem, OmniIconCatalog.solarSystemItem]
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private init() {}

    var categories: [String] {
        OmniCEFRLevel.allCases.map(\.rawValue)
    }

    func item(for id: String) -> OmniIconItem? {
        if id == OmniIconCatalog.imperialChronoItem.id {
            return items.first { $0.id == id } ?? OmniIconCatalog.imperialChronoItem
        }
        if id == OmniIconCatalog.solarSystemItem.id {
            return items.first { $0.id == id } ?? OmniIconCatalog.solarSystemItem
        }
        return items.first { $0.id == id }
    }

    @discardableResult
    func refresh() async -> Bool {
        guard !isLoading else { return !items.isEmpty }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched: [OmniIconItem] = try await supabase
                .from("omni_icon_catalog")
                .select("id, name, tier, asset_name, alternate_icon_name, subtitle, is_extra_exclusive, points_required, streak_days_required, rarity, category, category_sort_order, sort_order")
                .eq("is_active", value: true)
                .order("sort_order", ascending: true)
                .execute()
                .value
            var list = fetched
            if !list.contains(where: { $0.id == OmniIconCatalog.imperialChronoItem.id }) {
                list.append(OmniIconCatalog.imperialChronoItem)
            }
            if !list.contains(where: { $0.id == OmniIconCatalog.solarSystemItem.id }) {
                list.append(OmniIconCatalog.solarSystemItem)
            }
            items = list
            loadError = nil
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    /// The server validates the real streak before unlocking anything.
    func checkAndUnlockStreakIcons(userId: String?) {
        guard userId != nil else { return }
        Task {
            do {
                let result = try await OmniRewardRepository.unlockStreakIcons()
                if let icons = result.unlocked_omni_icons {
                    var merged = Set(icons)
                    let localRaw = UserDefaults.standard.string(forKey: "unlocked_omni_icon_ids") ?? ""
                    for item in localRaw.split(separator: ",").map(String.init) where !item.isEmpty {
                        merged.insert(item)
                    }
                    UserDefaults.standard.set(Array(merged).joined(separator: ","), forKey: "unlocked_omni_icon_ids")
                }
            } catch {
                print("Không thể đồng bộ Omnicon theo chuỗi: \(error.localizedDescription)")
            }
        }
    }
}

struct OmniShopItem: Identifiable, Equatable, Decodable {
    let id: String
    let name: String
    let subtitle: String
    let icon_name: String
    let color_start: String
    let color_end: String
    let points_cost: Int
    let is_extra_only: Bool
    let disabled_in_extra: Bool
    let extra_disabled_text: String
    let sort_order: Int

    var iconName: String { icon_name }
    var iconColors: [Color] { [Color(hex: color_start), Color(hex: color_end)] }
    var pointsCost: Int { points_cost }
    var isExtraOnly: Bool { is_extra_only }
    var disabledInExtra: Bool { disabled_in_extra }
    var extraDisabledText: String { extra_disabled_text }
}

@MainActor
final class OmniItemCatalog: ObservableObject {
    static let shared = OmniItemCatalog()
    @Published private(set) var items: [OmniShopItem] = []

    private init() {}

    func item(for id: String) -> OmniShopItem? { items.first { $0.id == id } }

    @discardableResult
    func refresh() async -> Bool {
        do {
            let fetched: [OmniShopItem] = try await supabase
                .from("omni_item_catalog")
                .select("id, name, subtitle, icon_name, color_start, color_end, points_cost, is_extra_only, disabled_in_extra, extra_disabled_text, sort_order")
                .eq("is_active", value: true)
                .order("sort_order", ascending: true)
                .execute()
                .value
            items = fetched
            return true
        } catch {
            print("Không thể tải danh mục vật phẩm: \(error.localizedDescription)")
            return false
        }
    }
}
