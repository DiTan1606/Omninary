import Foundation

// The four adventure regions, their fifteen stages each, and the quest flavour texts.

struct AdventureRegion: Identifiable, Equatable {
    let key: String, name: String, need: Int
    let stages: [String]
    var id: String { key }

    /// The stage island (index 0…14); generated, so every learner sees the same map.
    func map(_ index: Int) -> TileMap {
        switch key {
        case "lake": IslandMaps.genStage("lake", index + 1)
        case "city": IslandMaps.genCity(index + 1)
        case "desert": IslandMaps.genDesert(index + 1)
        default: IslandMaps.genStage("forest", index + 1)
        }
    }

    static let all: [AdventureRegion] = [
        .init(key: "forest", name: "Rừng Thì Thầm", need: 0, stages: ["Lối mòn đầu rừng", "Bụi mọng tím", "Suối thì thầm", "Bãi nấm đỏ", "Gốc cổ thụ", "Hang cú mèo", "Thung lũng dương xỉ", "Cầu gỗ cũ", "Rừng sương mù", "Đồi thông", "Trại tiều phu", "Hồ nước ẩn", "Cây ngàn năm", "Đêm trăng rằm", "Trái tim khu rừng"]),
        .init(key: "lake", name: "Hồ Gương", need: 30, stages: ["Bến cá sáng sớm", "Đầm sen hồng", "Bãi vỏ sò", "Nhà chài ven hồ", "Cầu câu dài", "Lau sậy xào xạc", "Chợ cá chiều", "Đảo nhỏ giữa hồ", "Mùa cá về", "Hoàng hôn trên hồ", "Thuyền đánh cá", "Bờ đá cuội", "Hồ gương đêm", "Lễ hội đèn nước", "Đáy hồ huyền bí"]),
        .init(key: "city", name: "Phố Chữ", need: 80, stages: ["Ngã tư chữ cái", "Hiệu sách góc phố", "Chợ chữ buổi sáng", "Trạm xe buýt", "Quảng trường đồng hồ", "Phố bảng hiệu", "Nhà in cũ", "Quán cà phê sách", "Công viên giữa phố", "Đại lộ ánh đèn", "Thư viện lớn", "Bến cảng thành phố", "Phố đêm", "Lễ hội đường phố", "Tháp chữ trung tâm"]),
        .init(key: "desert", name: "Sa Mạc Vang", need: 150, stages: ["Cồn cát đầu tiên", "Đồi cát vàng", "Đoàn lạc đà", "Chợ phiên sa mạc", "Đá đỏ", "Hang đá cổ", "Tàn tích cột đá", "Bão cát", "Làng nhà đất", "Hoá thạch khổng lồ", "Kim tự tháp nhỏ", "Đêm sao sa mạc", "Hẻm núi vang", "Thành cổ bị vùi", "Kim tự tháp vang"])
    ]

    static let acts: [String: (String, String)] = [
        "mushroom": ("Hái nấm đỏ", "Nấm đỏ mọc thành vòng, mỗi cây giấu một chữ."), "berry": ("Hái quả mọng", "Bụi mọng tím đung đưa trong gió."), "herb": ("Tìm thảo dược", "Lá thảo dược có khắc chữ nhỏ."), "log": ("Nhặt củi khô", "Khúc gỗ có vết khắc một từ."),
        "owl": ("Hỏi bác Cú", "Bác Cú: Ta hỏi một câu, cháu trả lời nhé!"), "woodcutter": ("Giúp bác Tiều Phu", "Bác Tiều Phu: Đọc giúp bác chữ khắc trên rìu này."), "stream": ("Lấy nước suối", "Suối chảy róc rách như đang đọc một từ."),
        "shell": ("Nhặt vỏ sò", "Vỏ sò áp tai vào nghe thấy một từ."), "reeds": ("Cắt sậy giúp làng", "Sậy cao quá che lối đi."), "buyfish": ("Bán cá cho chú Tám", "Chú Tám: Gọi đúng tên giúp chú nhé."), "net": ("Vá lưới", "Lưới rách thành từng mảnh chữ."), "fish": ("Câu cá", "Phao vừa động, kéo lên xem nào!"), "lotus": ("Hái sen hồng", "Bông sen nở ra một chữ."),
        "sign": ("Đọc bảng chữ", "Bảng hiệu bị mờ mất vài chữ."), "poster": ("Dán áp phích", "Áp phích còn thiếu một từ."), "newsstand": ("Ghé sạp báo", "Cô bán báo nhờ bạn đọc tít."), "letter": ("Gửi thư", "Phong bì cần ghi đúng một từ."), "bookseller": ("Giúp người bán sách", "Người bán sách: Cuốn này tên là gì nhỉ?"), "postman": ("Giúp bác Đưa Thư", "Bác Đưa Thư: Địa chỉ ghi từ gì đây?"),
        "pottery": ("Bình gốm cổ", "Hoa văn trên bình là một từ."), "fossil": ("Đào hoá thạch", "Hoá thạch in dấu một chữ."), "cactusfruit": ("Hái quả xương rồng", "Quả chín đỏ, cẩn thận gai!"), "gem": ("Nhặt đá quý", "Viên đá phát sáng khi gọi đúng tên."), "merchant": ("Mặc cả với lái buôn", "Lái buôn: Trả lời đúng thì ta giảm giá."), "nomad": ("Giúp người du mục", "Người du mục: Ta lạc đường, chỉ giúp ta!")
    ]
}
