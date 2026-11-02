#if DEBUG
import SwiftUI

/// Debug gallery of full word cards with real rows, opened with the -WordCardPreview launch argument.
struct WordCardPreview: View {
    static let samples: [Vocabulary] = [
        Vocabulary(id: "preview-1", vocab: "stay up late", CEFR: "B2", IPA: "/steɪ ʌp leɪt/", word_form: "phrasal verb",
                   E_meaning: "To remain awake and not go to bed until a late time at night.",
                   EV_meaning: "Thức và không đi ngủ cho đến một thời điểm muộn vào ban đêm.",
                   V_meaning: "thức khuya",
                   E_example: "In big cities, employees frequently stay up late working in order to meet deadlines and remain competitive in the job market.",
                   V_example: "Ở các thành phố lớn, nhân viên thường xuyên thức khuya làm việc để kịp deadline và giữ được sức cạnh tranh trên thị trường lao động.",
                   learning_level: 4, next_review: "2026-11-02T00:00:00Z", card_no: 1, art_path: "cards/001.png"),
        Vocabulary(id: "preview-16", vocab: "force", CEFR: "B2", IPA: "/fɔːrs/", word_form: "noun - countable",
                   E_meaning: "A push or pull that changes how something moves.",
                   EV_meaning: "Một tác động đẩy hoặc kéo làm thay đổi trạng thái chuyển động của một vật thể.",
                   V_meaning: "lực (đại lượng vật lý)",
                   E_example: "Gravity is a natural force that pulls objects towards the earth.",
                   V_example: "Trọng lực là một lực tự nhiên kéo các vật thể về phía trái đất.",
                   learning_level: 0, next_review: "2026-11-02T00:00:00Z", card_no: 16, art_path: "cards/016.png"),
        Vocabulary(id: "preview-174", vocab: "lay off", CEFR: "B2", IPA: "/leɪ ɑːf/", word_form: "phrasal verb",
                   E_meaning: "To stop employing a worker (either temporarily or permanently) because of business or financial needs rather than job performance.",
                   EV_meaning: "Cho một người lao động thôi việc, tạm thời hoặc vĩnh viễn, vì nhu cầu kinh doanh hoặc tài chính thay vì hiệu quả làm việc của họ.",
                   V_meaning: "cắt giảm nhân sự/cho người lao động thôi việc",
                   E_example: "Governments should provide support for people who are laid off unexpectedly.",
                   V_example: "Chính phủ nên hỗ trợ những người lao động bất ngờ bị cắt giảm.",
                   learning_level: 7, next_review: "2026-11-02T00:00:00Z", card_no: 174, art_path: "cards/174.png"),
        Vocabulary(id: "preview-26", vocab: "campus", CEFR: "B2", IPA: "/ˈkæmpəs/", word_form: "noun",
                   E_meaning: "All the buildings of a college or university, and the land around them.",
                   EV_meaning: "Tổ hợp các tòa nhà và toàn bộ khu đất thuộc quyền sở hữu hoặc sử dụng của một trường cao đẳng hoặc đại học.",
                   V_meaning: "khuôn viên trường",
                   E_example: "Modern universities invest heavily in campus facilities to attract students who enroll in their programs.",
                   V_example: "Các trường đại học hiện đại đầu tư mạnh vào cơ sở vật chất trong khuôn viên trường để thu hút sinh viên đăng ký vào các chương trình của họ.",
                   learning_level: 10, next_review: "2026-11-02T00:00:00Z", card_no: 26, art_path: "cards/026.png")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(Self.samples, id: \.id) { WordCardView(vocab: $0, mastery: 80, mode: .full) }
            }
            .padding(.vertical, 24).frame(maxWidth: .infinity)
        }
        .background(Color(hex: 0xe8eee4))
    }
}
#endif
