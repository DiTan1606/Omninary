import Foundation
import Testing
@testable import Omninary

@MainActor
struct AppIconManagerTests {
    @Test
    func everyCatalogOmniconHasABundledAlternateIcon() {
        let catalogIDs = [
            "extraordinary_aurora",
            "omni_streak_30", "omni_streak_100", "omni_streak_200", "omni_streak_300",
            "omni_season_spring", "omni_season_summer", "omni_season_autumn", "omni_season_winter",
            "omni_legendary_celestial_oracle", "omni_legendary_imperial_koi",
            "omni_mythic_jade_dragon", "omni_mythic_imperial_chrono"
        ]

        #expect(AppIconManager.alternateIconName(for: "ditandnary_classic") == nil)
        for id in catalogIDs {
            #expect(AppIconManager.alternateIconName(for: id) != nil)
        }

        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any]
        for name in AppIconManager.bundledIconNamesById.values {
            #expect(alternates?[name] != nil)
        }
    }

}
