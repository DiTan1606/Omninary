import CoreGraphics
import Foundation

// 16×16 pixel icons for word cards, picked by matching the Vietnamese meaning (demo art set).

enum WordArt {
    static let palette: [Character: UInt32] = ["k": 0x2b2238, "r": 0xe0453a, "R": 0xa8282a, "w": 0xffffff, "g": 0x58b84a, "G": 0x2f7d3a, "b": 0x8a5a2b, "y": 0xf4c542, "o": 0xf08a24, "p": 0x9a5fd6, "P": 0x5b2d91, "l": 0x8ccdf7, "B": 0x2f6fd6, "n": 0xe9c98f, "m": 0x9aa2b2, "M": 0x5d6474, "c": 0xfff4d6, "s": 0xffd9b8, "e": 0xff9ab8]

    static let icons: [String: [String]] = [
        "moon": ["", ".....kkkk....w..", "...kkyyyk.......", "..kyyyyk........", ".kyyyyk.....w...", ".kyyyk..........", "kyyyyk..........", "kyyyyk...w......", "kyyyyk..........", "kyyyyyk.........", ".kyyyyyk.....kk.", ".kyyyyyykkkkkyk.", "..kyyyyyyyyyyk..", "...kkyyyyyykk...", ".....kkkkkk....."],
        "book": ["", "", ".kkkkkk..kkkkkk.", "kccccccbbcccccck", "kcMMMMcbbcMMMMck", "kccccccbbcccccck", "kcMMMMcbbcMMMck.", "kccccccbbcccccck", "kcMMMcbbbcMMMMck", "kccccccbbcccccck", "kBBBBBBbbBBBBBBk", ".kkkkkkkkkkkkkk.", "......kyyk......", "......kyyk......", ".......kk......."],
        "coin": ["", ".....kkkkkk.....", "...kkyyyyyykk...", "..kyyywyyyyyyk..", ".kyywyyooyyyyyk.", ".kywyyoyyoyyyok.", "kyyyyyoyyyyyyyok", "kyyyyyyooyyyyyok", "kyyyyyyyyoyyyyok", "kyyyyyoyyoyyyyok", ".kyyyyyooyyyyok.", ".kyyyyyyyyyyyok.", "..kyyyyyyyyyok..", "...kkooooookk...", ".....kkkkkk....."],
        "heart": ["", "", "..kkkk....kkkk..", ".krrrrk..krrrrk.", "krrwwrrkkrrrrrRk", "krwwrrrrrrrrrrRk", "krwrrrrrrrrrrrRk", "krrrrrrrrrrrrRRk", ".krrrrrrrrrrrRk.", "..krrrrrrrrrRk..", "...krrrrrrrRk...", "....krrrrrRk....", ".....krrrRk.....", "......krRk......", ".......kk......."],
        "medic": ["", "", ".....kkkkkk.....", ".....k....k.....", ".kkkkkkkkkkkkkk.", "kwwwwwwwwwwwwwwk", "kwwwwwkrrkwwwwmk", "kwwwwwkrrkwwwwmk", "kwwwkkkrrkkkwwmk", "kwwwkrrrrrrkwwmk", "kwwwkkkrrkkkwwmk", "kwwwwwkrrkwwwwmk", "kwwwwwkkkkwwwwmk", "kmmmmmmmmmmmmmmk", ".kkkkkkkkkkkkkk."],
        "bulb": ["......kkkk......", "....kkyyyykk....", "...kyywyyyyyk...", "..kyywyyyyyyyk..", "..kywyyyyyyyyk..", "..kyyyyyyyyyyk..", "..kyyyyyyyyyok..", "...kyyyyyyyok...", "....kyyyyyok....", ".....kyyyok.....", ".....kmmmmk.....", ".....kMMMMk.....", ".....kmmmmk.....", "......kMMk......", ".......kk......."],
        "house": ["", ".......kk.......", "......krrk......", ".....krrrrk.kk..", "....krrrrrrkbk..", "...krrrrrrrrkk..", "..krrrrrrrrrrk..", ".kRRRRRRRRRRRRk.", "..kccccccccccck.", "..kclllkcckbbkck", "..kclllkcckbbkck", "..kckkkkcckbbkck", "..kccccccckbbkck", "..kkkkkkkkkkkkkk", "gggggggggggggggg"],
        "brief": ["", "", "......kkkk......", ".....kbkkbk.....", ".....kb..bk.....", ".kkkkkkkkkkkkkk.", "kbbbbbbbbbbbbbbk", "kbnnnnnnnnnnnnbk", "kbbbbbbkkbbbbbbk", "kkkkkkkyykkkkkkk", "kbbbbbbkkbbbbbbk", "kbnnnnnnnnnnnnbk", "kbbbbbbbbbbbbbbk", ".kkkkkkkkkkkkkk.", ""],
        "speech": ["", ".kkkkkkkkkk.....", "kwwwwwwwwwwk....", "kwkkwkkkwwwk....", "kwwwwwwwwwwk....", "kwkkkwkkwwwk....", "kwwwwwwwwwwk....", ".kkkwkkkkkk.....", "...kwk..kkkkkkk.", "...kk..kllllllk.", "......kllkklkllk", "......kllllllllk", "......kllkkkkllk", "......kllllllllk", ".......kkkllkkk.", "...........kk..."],
        "journey": ["...........yy...", "..........yyyy..", "..........yyyy..", "...........yy...", "......k.........", ".....kmk........", "....kmwmk...k...", "...kmmmmmk.kmk..", "..kmmMmmmmkmmmk.", ".kmmMMmmmmmmMmmk", "kGgggggnnggggggk", "GggggggnnnggggGG", "ggggggnnnnnggggg", "gggggnnnnnnngggg", "ggggnnnnnnnnnggg", "gggnnnnnnnnnnngg"],
        "apple": ["", "........kk......", ".......kbk......", ".......kb.kkk...", "....kkkkbkggk...", "...krrrrkrkk....", "..krrwrrrrrrk...", "..krwrrrrrrrk...", "..krrrrrrrrRk...", "..krrrrrrrrRk...", "..krrrrrrrRRk...", "...krrrrrRRk....", "...krrrrRRRk....", "....krRkkRk.....", ".....kk..kk....."],
        "phone": ["", "....kkkkkkkk....", "...kMMMMMMMMk...", "...kMllllllMk...", "...kMlwllllMk...", "...kMlllllBMk...", "...kMllllBBMk...", "...kMlllBBBMk...", "...kMllBBBBMk...", "...kMlBBBBBMk...", "...kMBBBBBBMk...", "...kMMMMMMMMk...", "...kMMMkkMMMk...", "...kMMMMMMMMk...", "....kkkkkkkk...."],
        "ban": ["", ".....kkkkkk.....", "...kkrrrrrrkk...", "..krrkkkkkkrrk..", ".krrk......krrk.", ".krk......krRrk.", "krk......krRk.rk", "krk.....krRk..rk", "krk....krRk...rk", "krk...krRk....rk", "kr.krRk......krk", ".krrRk......krk.", ".krrk......krrk.", "..krrkkkkkkrrk..", "...kkrrrrrrkk...", ".....kkkkkk....."],
        "star": ["", ".......kk.......", "......kyyk......", "......kyyk......", ".....kyyyyk.....", "kkkkkkywyyykkkkk", "kyyyyywyyyyyyyok", ".kyyyyyyyyyyyok.", "..kyyyyyyyyyok..", "...kyyyyyyyok...", "...kyyyyyyyyk...", "..kyyyyookyyyk..", "..kyyokk.kkoyk..", ".kyok......koyk.", ".kkk........kkk."],
        "up": ["", ".......kk.......", "......kggk......", ".....kgggGk.....", "....kgggggGk....", "...kgggggggGk...", "..kkkkgggGkkkk..", ".....kgggGk.....", ".....kgggGk.....", ".....kgggGk.....", ".....kgggGk.....", ".kk..kgggGk..kk.", "kMMk.kgggGk.kMMk", "kMMk.kkkkkk.kMMk", "kMMkkkkkkkkkkMMk", "kkkkkkkkkkkkkkkk"],
        "clock": ["", ".....kkkkkk.....", "...kkwwwwwwkk...", "..kwwwwkwwwwwk..", ".kwwwwwkwwwwwwk.", ".kwkwwwkwwwwkwk.", "kwwwwwwkwwwwwwwk", "kwwwwwwkwwwwwwwk", "kwwwwwwkkkkkwwwk", "kwwwwwwwwwwwwwwk", ".kwkwwwwwwwwkwk.", ".kwwwwwwwwwwwwk.", "..kwwwwwkwwwwk..", "...kkwwwwwwkk...", ".....kkkkkk....."],
        "magnify": ["", "...kkkkk........", "..kllllllk......", ".kllwwlllllk....", "kllwllllllllk...", "klwlllllllllk...", "kllllllllllllk..", "kllllllllllllk..", "kllllllllllllk..", ".klllllllllllk..", "..kllllllllkk...", "...kkkkkkkkkbk..", "...........kbbk.", "............kbbk", ".............kbk", "..............k."],
        "people": ["", "...kkk....kkk...", "..kbbbk..kPPPk..", "..ksssk..ksssk..", "..ksksk..ksksk..", "..ksssk..ksssk..", "...kkk....kkk...", "..kBBBk..krrrk..", ".kBBBBBkkrrrrrk.", ".kBBBBBkkrrrrrk.", ".kBBBBBkkrrrrrk.", ".kkBBBkkkkrrrkk.", "..kMkMk..kMkMk..", "..kMkMk..kMkMk..", "..kkkkk..kkkkk.."],
        "impact": ["", ".......kk.......", "..kk..koyk..kk..", "..kyk.koyk.kyk..", "...kykoyyokyk...", "kk..kyyyyyyk..kk", "koyyyywwwyyyyyok", ".kooyywwwwyyook.", "..kkoywwwwyokk..", ".kooyyywwyyyook.", "koyyyyyyyyyyyyok", "kk..kyyyyyyk..kk", "...kykoyyokyk...", "..kyk.koyk.kyk..", "..kk..koyk..kk..", ".......kk......."],
        "globe": [".....kkkkkk.....", "...kkBBlBBBkk...", "..kBBggBBlBBBk..", ".kBgggggBBBggBk.", ".kBBgggBBBgggBk.", "kBBBBggBBBBggBBk", "kBlBBBBBBBBBgBBk", "kBBBBBBggBBBBBBk", "kBBBBBgggggBBlBk", "kBBlBBBgggBBBBBk", ".kBBBBBBgBBBBBk.", ".kBBggBBBBBBBBk.", "..kBgggBBBBlBk..", "...kkBBBBBBkk...", ".....kkkkkk....."],
        "check": ["", "..............kk", ".............kgk", "............kggk", "...........kggk.", "..........kggk..", ".kk......kggk...", "kggk....kggk....", "kgggk..kggk.....", ".kgggkkggk......", "..kgggggk.......", "...kgggk........", "....kgk.........", ".....k..........", "", ""],
        "scroll": ["", "..kkkkkkkkkkk...", ".kcccccccccccck.", "kcbkcccccccccbck", ".kkkcccccccccck.", "...kcMMMMMMMck..", "...kcccccccccck.", "...kcMMMMMcccck.", "...kcccccccccck.", "...kcMMMMMMMck..", "...kcccccccccck.", ".kkkcccccccccck.", "kcbkcccccccccbck", ".kcccccccccccck.", "..kkkkkkkkkkk..."]
    ]

    /// Keyword rules: the first rule whose phrase appears as a whole phrase in the meaning wins.
    static let rules: [(String, String)] = [
        ("moon", "thức khuya|ác mộng|ban đêm|ngủ"),
        ("medic", "bệnh|bệnh tiểu đường|bệnh béo phì|béo phì|thừa cân|chóng mặt|kiệt sức|cơn co giật|tim mạch|khám sức khoẻ"),
        ("book", "học|học phí|giáo dục bậc đại học|chương trình học|ký túc xá|khuôn viên trường|chứng chỉ|chứng nhận|chuyên ngành đại học|tác giả|thể loại|bỏ học|đăng ký|kỳ thi|sự nhận vào"),
        ("coin", "tiền cọc|gửi tiền|chi trả|có mức giá vừa phải|vô giá|tăng lương|nền kinh tế|cho vay|kiếm được|trung lưu|tiêu thụ"),
        ("apple", "chế độ ăn|ăn kiêng|việc ăn quá mức|dinh dưỡng|đầu bếp|chanh|trà sữa trân châu|nhạt nhẽo|có mùi|mùi|hữu cơ|phần mềm gọi đồ ăn"),
        ("heart", "khỏe mạnh|về mặt thể chất|hít thở|về mặt tinh thần|lợi ích|có lợi|làm lợi cho ai đó|sẵn lòng|ấm cúng"),
        ("brief", "đồng nghiệp|ngành|lịch làm việc|văn hóa làm việc|sự làm việc quá mức|làm việc quá mức|cắt giảm|hội đồng quản trị|việc nhà hàng ngày|chăm chỉ|hãng sản xuất|tiến hành"),
        ("speech", "thảo luận|tranh luận|giao tiếp xã hội|giữ liên lạc|biểu lộ|khuyên nhủ|phản đối|biểu tình|sự phản đối|lời đề nghị|quảng cáo|chỉ trích|trực tiếp"),
        ("journey", "điểm đến|đáng ghé thăm|việc đi ngắm cảnh|lịch trình|nước ngoài|khởi hành|cảnh quan|làm quang cảnh|nhìn ra|đi lang thanh|sự lang thang|tốc hành|lướt|về phía sau|lùi lại"),
        ("house", "rộng rãi|sự riêng tư|sự ở lại|giữ trạng thái gì"),
        ("phone", "thiết bị|nền tảng|ảo|sự tiếp cận|tiếp cận"),
        ("ban", "cấm|lệnh cấm|bắt buộc|áp đặt|ép buộc|loại bỏ|sự tổn hại|gây hại cho ai đó/cái gì đó|bạo lực|nghiêm khắc|hà khắc|cực đoan|cực điểm|sụp đổ|sự sụp đổ|không phù hợp|khẩn cấp|sự ùn tắc|rác|chịu đựng"),
        ("star", "vinh quang|nổi trội|điểm sáng|gây ấn tượng|lôi cuốn|có tính lịch sử|quan trọng"),
        ("up", "tăng|mắc|phát triển|vượt qua|hình thành|duy trì|năng lực|quyết tâm|xoay sở"),
        ("clock", "đúng giờ|tốc độc|nhịp|rốt cuộc thì|tốn thời gian|ưu tiên|xuyên suốt"),
        ("bulb", "dự đoán|trực giác|sự tò mò|tìm ra câu trả lời|cảm thấy|ý thức|khiến hứng thú|sự quan tâm|đắm chìm"),
        ("magnify", "phát hiện|hé lộ|màn hé lộ|chi tiết|chính xác|đặc điểm"),
        ("people", "hợp tác|chính quyền|tham gia|ở giữa|kết hợp|liên quan đến cái gì|bao gồm|cho phép|loại hình"),
        ("impact", "lực|sự va chạm|tác động|sự ảnh hưởng|ảnh hưởng|khiến cho ai đó"),
        ("check", "điều chỉnh|đảm bảo|thực tế|bỏ qua|cung cấp|chắc chắn")
    ]
    private static let compiled: [(String, NSRegularExpression)] = rules.compactMap { key, phrases in
        guard let re = try? NSRegularExpression(pattern: "(?:^|[\\s,;(/])(?:" + phrases + ")(?=$|[\\s,;)/])", options: [.caseInsensitive]) else { return nil }
        return (key, re)
    }

    static func key(meaning: String?, extra: String?) -> String {
        func match(_ text: String) -> String? {
            let t = " " + text + " ", range = NSRange(t.startIndex..., in: t)
            return compiled.first { $0.1.firstMatch(in: t, range: range) != nil }?.0
        }
        if let m = meaning, let k = match(m) { return k }
        if let k = match((meaning ?? "") + " , " + (extra ?? "")) { return k }
        return "scroll"
    }

    private static var cache: [String: CGImage] = [:]
    static func image(_ key: String) -> CGImage? {
        if let c = cache[key] { return c }
        let rows = icons[key] ?? icons["scroll"]!, canvas = PixelCanvas(width: 16, height: 16)
        let shift = rows.count < 16 ? 1 : 0
        for (j, row) in rows.enumerated() {
            for (i, ch) in row.prefix(16).enumerated() { if let c = palette[ch] { canvas.R(i, j + shift, 1, 1, c) } }
        }
        let img = canvas.makeImage(); cache[key] = img; return img
    }
}
