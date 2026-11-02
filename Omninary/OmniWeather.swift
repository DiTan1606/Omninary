import CoreLocation
import Foundation

/// What the sky on the new pages should show.
enum OmniWeatherKind: String, CaseIterable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, storm, snow

    var title: String {
        switch self {
        case .clear: "Trời quang"
        case .partlyCloudy: "Có mây"
        case .cloudy: "Nhiều mây"
        case .fog: "Sương mù"
        case .drizzle: "Mưa phùn"
        case .rain: "Mưa"
        case .storm: "Giông"
        case .snow: "Tuyết"
        }
    }

    /// WMO weather codes as Open-Meteo reports them. For the dry codes 0–3 the sky follows the
    /// cloud cover that actually blocks the sun (see `OmniWeather.effectiveCover`), and strong direct
    /// sunshine keeps the sun out even when thin high cloud makes Open-Meteo say "overcast".
    init(code: Int, cloudCover: Int?, sunny: Bool = false) {
        switch code {
        case 0, 1, 2, 3:
            let cover = cloudCover ?? 0
            if cover <= 35 || (sunny && cover <= 60) { self = .clear }
            else if cover <= 70 || sunny { self = .partlyCloudy }
            else { self = .cloudy }
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57: self = .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .storm
        default: self = .partlyCloudy
        }
    }
}

/// Local weather for the sky: approximate location, Open-Meteo (free, no key), refreshed every 15 minutes (its data step).
/// Without location permission it uses Hồ Chí Minh City.
@MainActor
final class OmniWeather: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = OmniWeather()
    /// DEBUG and screenshots: `-weather_preview rain` forces a kind.
    static let previewKey = "weather_preview"

    @Published private(set) var kind: OmniWeatherKind = .clear
    @Published private(set) var temperature: Double?
    @Published private(set) var weatherCode: Int?
    /// Real cloud cover in percent; nil until the first fetch.
    @Published private(set) var cloudCover: Int?
    /// Wind at 10 m in km/h; drives how fast the clouds drift.
    @Published private(set) var windSpeed: Double?
    /// Strong direct sunshine right now (daytime and at least 300 W/m² reaching the ground).
    @Published private(set) var sunny = false
    /// Day or night at the learner's place, from Open-Meteo's `is_day` (sun above the horizon);
    /// nil until the first fetch. The interface's automatic day/night follows it.
    @Published private(set) var isDay: Bool?

    /// Cloud that actually hides the sky: low and mid cloud count fully, thin high cirrus only a quarter.
    /// Open-Meteo's total counts cirrus fully, so a bright sunny morning can read "90% overcast".
    static func effectiveCover(total: Int?, low: Int?, mid: Int?, high: Int?) -> Int? {
        guard low != nil || mid != nil || high != nil else { return total }
        let thick = max(low ?? 0, mid ?? 0)
        return min(100, thick + (high ?? 0) / 4)
    }
    @Published private(set) var updatedAt: Date?

    private let manager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var isFetching = false
    private static let fallback = CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297)

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// The weather sky is always on now (its switch left Setting); kept as one place to turn it off.
    var isEnabled: Bool { true }

    /// Shown kind, honouring the preview override.
    var shownKind: OmniWeatherKind {
        if let raw = UserDefaults.standard.string(forKey: Self.previewKey), let k = OmniWeatherKind(rawValue: raw) { return k }
        return isEnabled ? kind : .partlyCloudy
    }

    /// Cloud cover shown in the sky: the real value, or a typical one for a preview or a disabled sky.
    var shownCloudCover: Int {
        if UserDefaults.standard.string(forKey: Self.previewKey) == nil, isEnabled, let cloudCover { return cloudCover }
        switch shownKind {
        case .clear: return 5
        case .partlyCloudy: return 30
        case .cloudy, .fog, .snow: return 70
        case .drizzle, .rain, .storm: return 95
        }
    }

    /// Cloud drift speed factor from the real wind (1 = a light breeze).
    var cloudSpeedFactor: Double {
        guard let windSpeed, isEnabled else { return 1 }
        return min(4, max(0.4, windSpeed / 10))
    }

    /// Two words for the greeting, e.g. "Chói chang" or "Mưa rào".
    func descriptor(night: Bool) -> String {
        let shown = shownKind
        let code = UserDefaults.standard.string(forKey: Self.previewKey) == nil ? weatherCode : nil
        switch shown {
        case .storm: return "Giông bão"
        case .snow: return "Tuyết rơi"
        case .fog: return "Sương mờ"
        case .drizzle: return "Mưa phùn"
        case .rain:
            switch code {
            case 61, 80: return "Mưa phùn"
            case 65, 67, 82: return "Tầm tã"
            default: return "Mưa rào"
            }
        default: break
        }
        let cover = shownCloudCover
        if cover > 80 { return "Âm u" }
        if cover > 40 { return "Nhiều mây" }
        if cover > 10 && !sunny { return "Mây thưa" }
        if night { return "Trời trong" }
        if let temperature, isEnabled, sunny || cover <= 10 {
            if temperature >= 33 { return "Nực nội" }
            if temperature >= 30 { return "Chói chang" }
        }
        return "Quang đãng"
    }

    func refreshIfNeeded() {
        guard isEnabled else { return }
        if let updatedAt, Date().timeIntervalSince(updatedAt) < 15 * 60 { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: Task { await fetch(Self.fallback) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: await self.fetch(Self.fallback)
            default: break
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.coordinate = c; await self.fetch(c) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in await self.fetch(self.coordinate ?? Self.fallback) }
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let weather_code: Int; let cloud_cover: Int?; let temperature_2m: Double?; let wind_speed_10m: Double?
            let cloud_cover_low: Int?; let cloud_cover_mid: Int?; let cloud_cover_high: Int?
            let direct_radiation: Double?; let is_day: Int?
            /// Precipitation of the last 15 minutes, in mm.
            let precipitation: Double?
        }
        let current: Current
    }

    private func fetch(_ c: CLLocationCoordinate2D) async {
        guard !isFetching else { return }
        isFetching = true; defer { isFetching = false }
        // Two decimals (~1 km) is all the sky needs.
        let lat = String(format: "%.2f", c.latitude), lon = String(format: "%.2f", c.longitude)
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=weather_code,cloud_cover,temperature_2m,wind_speed_10m,cloud_cover_low,cloud_cover_mid,cloud_cover_high,direct_radiation,is_day,precipitation") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(Response.self, from: data)
            let c = r.current
            let cover = Self.effectiveCover(total: c.cloud_cover, low: c.cloud_cover_low, mid: c.cloud_cover_mid, high: c.cloud_cover_high)
            let sun = (c.is_day ?? 1) == 1 && (c.direct_radiation ?? 0) >= 300
            // Open-Meteo's code and precipitation are the model's estimate and often say a trace of
            // drizzle on a dry, sunny afternoon. Rain, drizzle and storms only show for a real amount
            // (at least 0.2 mm in 15 minutes) and not while the sun is still reaching the ground;
            // otherwise the sky follows the clouds.
            let wet = (51...67).contains(c.weather_code) || (80...82).contains(c.weather_code) || c.weather_code >= 95
            let sunThrough = (c.is_day ?? 1) == 1 && (c.direct_radiation ?? 0) >= 100
            let raining = (c.precipitation ?? 0) >= 0.2 && !sunThrough
            let code = wet && !raining ? 3 : c.weather_code
            kind = OmniWeatherKind(code: code, cloudCover: cover, sunny: sun)
            temperature = c.temperature_2m
            weatherCode = code
            cloudCover = cover
            sunny = sun
            isDay = c.is_day.map { $0 == 1 }
            windSpeed = r.current.wind_speed_10m
            updatedAt = Date()
        } catch {
            // Keep the last sky; try again next time a page appears.
        }
    }
}
