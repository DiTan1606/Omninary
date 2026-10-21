> Cập nhật 28/09/2026: mô hình hiện hành là mỗi bản ghi `vocab_catalog.id` = một từ vựng độc lập. Tầng gom theo cách viết và nhóm hiển thị đã được gỡ. Xem [VOCABULARY_ITEMS.md](VOCABULARY_ITEMS.md). Các mô tả nhóm trong tài liệu này chỉ ghi lại giai đoạn triển khai trước.

# Kho từ vựng dạng thư mục và thẻ nghĩa

Đã áp dụng `vocabulary_workspace.sql` trên Supabase ngày 27/09/2026.
Trước và sau chuyển đổi đều có 195 nghĩa và 126 bản ghi tiến độ; mã kiểm tra toàn bộ
tiến độ và danh sách mã nghĩa trùng khớp. Các thao tác thử trực tiếp trên máy chủ được
đặt trong giao dịch hoàn tác, không để lại dữ liệu thử.

## Vị trí gốc

`user_vocabulary_workspace` lưu chủ đề gốc riêng của mỗi người, có tên “Bộ từ gốc”.
Tạo khi người học mở kho lần đầu; dùng lại cùng mã ở các lần sau. Trang gốc hiển thị
nghĩa thuộc chủ đề này trực tiếp, không hiển thị nó như một thư mục con. Thư mục gốc
không được xoá, đổi tên hoặc đưa lên hệ thống.

Không tự đưa mọi nghĩa ra trang gốc. Một nghĩa có thể đồng thời nằm ở gốc và thư mục
khác khi người dùng chọn “Thêm vào”. Nghĩa không còn thuộc thư mục nào được đặt vào
gốc khi làm mới kho, bao gồm trường hợp xoá thư mục và dùng máy khách cũ.

## Các thao tác

- “Di chuyển”: thêm vào nơi đến và gỡ khỏi nơi đang mở trong cùng giao dịch.
- “Thêm vào thư mục khác”: giữ nơi đang mở và thêm liên kết đến thư mục riêng đã chọn.
- “Đưa ra thư mục gốc”: di chuyển từ thư mục đang mở sang “Bộ từ gốc”; giữ các nơi khác.
- “Gỡ khỏi thư mục này”: chỉ gỡ liên kết hiện tại; nếu không còn nơi nào thì trở về gốc.
- “Xoá khỏi kho học”: cần xác nhận, xoá tiến độ riêng của người dùng và mọi liên kết
  hiển thị của nghĩa đó. Nội dung trong danh mục vẫn giữ để có thể dùng lại.
- “Hoàn tác”: khôi phục vị trí và nhóm hiển thị trước thao tác gần nhất; không sửa cấp
  độ, lịch ôn hay điểm. Không hoàn tác xoá khỏi kho học hoặc xoá thư mục.

Người học sắp xếp vào thư mục riêng. Các thư mục tải từ hệ thống vẫn dùng quy tắc nội
dung công khai có sẵn; việc gỡ khỏi bộ sưu tập cá nhân không sửa bộ từ công khai.

## Nhóm theo từ

`vocabulary_display_groups` lưu người dùng, vị trí và mã từ. `user_topic_vocab.display_group_id`
đánh dấu đúng những nghĩa người dùng chọn. Không tự nhóm nghĩa cùng cách viết; không
thêm nghĩa mới vào nhóm; không áp nhóm từ một thư mục sang thư mục khác.

Nhóm chỉ tạo thẻ hiển thị có thể mở rộng. Mỗi nghĩa vẫn có mã và tiến độ riêng. Nếu
chỉ còn một nghĩa trong nhóm, nó hiển thị như thẻ nghĩa đơn. Bỏ nhóm không đổi vị trí.
Các thao tác được kiểm tra quyền phía máy chủ và tuần tự hoá theo người dùng.

## Giao diện iPhone

`MyVocabularyView` dùng `VocabularyWorkspaceBrowser` với trạng thái chung tại
`VocabularyWorkspaceStore`. Trang gốc cho tạo thư mục hoặc nghĩa; trong thư mục chỉ
cho tạo/thêm nghĩa. Thẻ có nút “…” và thao tác nhấn giữ; “Chọn” cho phép chọn nhiều
nghĩa để di chuyển, thêm vào nơi khác, gỡ, nhóm hoặc xoá.

Mở thẻ nghĩa vẫn dùng màn hình chi tiết, sửa nội dung và đưa vào học có sẵn. Nhóm
hiển thị mở rộng ngay tại trang hiện tại, không trở thành thư mục con.

## Kiểm tra

```sh
node supabase/tests/vocabulary_topic_memberships_test.mjs /tmp/omninary-streak-pg
python3 supabase/tests/vocabulary_rest_relationships_test.py
```

Bộ kiểm tra cơ sở dữ liệu gồm 31 kiểm tra nền và 27 kiểm tra kho dạng thư mục. Kiểm tra
Swift xác nhận chỉ nhóm các nghĩa được chọn tại đúng vị trí và giữ tiến độ độc lập.
Kiểm tra giao diện dùng dữ liệu mẫu trong bản phát triển, không ghi lên Supabase.
