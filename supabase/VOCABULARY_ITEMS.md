# Từ vựng độc lập — mô hình hiện hành

Mỗi bản ghi `vocab_catalog.id` là một từ vựng, một đơn vị học độc lập. Trường `word` là cách viết, không phải mã định danh. Các mục có cách viết giống nhau vẫn có thể khác phiên âm, từ loại, nghĩa, ví dụ, cách dùng và tiến độ.

- `topics`: bộ từ để sắp xếp nội dung.
- `vocab_catalog`: nội dung từng từ vựng.
- `topic_vocab`: liên kết bộ từ với từ vựng trong danh mục.
- `user_vocabulary`: tiến độ cá nhân; ràng buộc duy nhất `(user_id, vocab_id)`.
- `user_topic_vocab`: những bộ từ người dùng đặt một từ vựng đã lưu vào, tham chiếu cùng một bản ghi tiến độ.
- `user_vocabulary_workspace`: vị trí gốc riêng “Bộ từ gốc”.

Tạo mới luôn tạo mã mới và tiến độ mới. Thêm từ vựng đã có vào bộ từ khác dùng lại mã, cấp độ, thời điểm ôn và lịch sử. Chuyển, gỡ liên kết và hoàn tác không sửa tiến độ. Gỡ liên kết cuối đưa mục về trang gốc; xoá khỏi kho học là thao tác riêng.

Không còn bảng `vocabulary_words`, cột `vocab_catalog.word_id`, bảng `vocabulary_display_groups`, cột `user_topic_vocab.display_group_id` hoặc thao tác nhóm. Ứng dụng iPhone, Khám phá và bản web hiển thị theo mã từ vựng, không gom theo cách viết. Các thuộc tính nghĩa vẫn là nội dung của từ vựng; không còn là một tầng đối tượng con.

## Triển khai

Migration (bản cập nhật cấu trúc dữ liệu) mới: `vocabulary_independent_items.sql`, sau đó áp dụng `vocabulary_root_collection_name.sql` để đổi tên bộ gốc mà giữ nguyên mã. Bản độc lập áp dụng sau hai bản cập nhật lịch sử `vocabulary_topic_memberships.sql` và `vocabulary_workspace.sql`. Không chạy lại hai bản lịch sử sau bản mới.

Hàm tạo chính là `create_vocabulary_item`. Tên cũ `create_vocabulary_meaning` chỉ là bí danh tương thích, gọi cùng hàm tạo mới; không tạo tầng nghĩa hoặc nhóm. Các hàm lưu và gỡ liên kết giữ tên cũ để tránh đổi các luồng quản trị không cần thiết.

Đã áp dụng trực tiếp lên Supabase. Bản cập nhật khoá ghi ngắn trong giao dịch và so sánh toàn bộ nội dung, tiến độ, liên kết trước/sau; nếu khác ngoài dữ liệu gom bị bỏ thì tự huỷ giao dịch. Tại thời điểm triển khai: 196 từ vựng và 137 tiến độ được giữ nguyên, liên kết bộ từ không đổi. Các mã từ vựng và tham chiếu lịch sử học không được viết lại.

Cần biên dịch lại ứng dụng iPhone và cập nhật bản web để sử dụng truy vấn không còn yêu cầu các cột nhóm cũ.

## Kiểm tra

`node supabase/tests/vocabulary_topic_memberships_test.mjs /private/tmp/omninary-streak-pg` chạy lần lượt kiểm tra các giai đoạn lịch sử và mô hình hiện hành trên cơ sở dữ liệu cục bộ tách biệt: bảo toàn dữ liệu, cùng cách viết nhưng khác mã/phiên âm/cấp độ, dùng một tiến độ qua nhiều bộ từ, di chuyển/hoàn tác, quyền riêng tư và chạy lại bản cập nhật.

Kiểm tra Swift và web xác nhận hai bản ghi cùng cách viết vẫn là hai mục. Kiểm tra truy vấn thật dùng `supabase/tests/vocabulary_rest_relationships_test.py`. Kiểm tra trực tiếp các hàm trên Supabase dùng giao dịch hoàn tác để không để lại nội dung thử nghiệm.
