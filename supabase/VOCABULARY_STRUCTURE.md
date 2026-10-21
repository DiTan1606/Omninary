> Cập nhật 28/09/2026: mô hình hiện hành là mỗi bản ghi `vocab_catalog.id` = một từ vựng độc lập. Tầng gom theo cách viết và nhóm hiển thị đã được gỡ. Xem [VOCABULARY_ITEMS.md](VOCABULARY_ITEMS.md). Các mô tả nhóm trong tài liệu này chỉ ghi lại giai đoạn triển khai trước.

# Nền tảng từ vựng: từ — nghĩa — bộ sưu tập

## Cấu trúc chính

- `vocabulary_words`: từ/cụm từ có mã ổn định, gom theo cách viết tiếng Anh đã chuẩn hoá.
- `vocab_catalog`: mỗi bản ghi là một nghĩa, tham chiếu `word_id`. Giữ nguyên các mã nghĩa hiện có.
- `topics`: bộ sưu tập hệ thống hoặc riêng của người dùng.
- `topic_vocab`: một nghĩa có thể xuất hiện trong nhiều bộ sưu tập nội dung.
- `user_vocabulary`: một tiến độ duy nhất cho mỗi cặp người học–nghĩa.
- `user_topic_vocab`: những bộ sưu tập mà người học đã chọn lưu nghĩa vào. Tham chiếu tiến độ, không sao chép tiến độ.

Giao diện vẫn trình bày chủ đề → từ → các nghĩa đã chọn của từ. Luồng ôn đọc
`user_vocabulary` một lần, không nhân bản bản ghi theo số bộ sưu tập.

Ví dụ: nghĩa “ngân hàng” đã ở cấp 4 trong Kinh doanh. Thêm đúng mã nghĩa đó
vào IELTS chỉ tạo liên kết mới; cấp 4, lịch ôn, điểm phát âm và lịch sử vẫn giữ nguyên.
Nghĩa “bờ sông” là bản ghi khác, bắt đầu ở cấp 0 dù thuộc cùng từ “bank”.

## Các thao tác

- Tạo nghĩa mới: `create_vocabulary_meaning` tạo nội dung và lưu vào kho trong một giao dịch.
- Thêm nghĩa đã có / tải chủ đề: `save_vocabulary_to_topic`. Lưu trùng không cập nhật tiến độ.
- Gỡ khỏi chủ đề: `remove_vocabulary_from_topic`; không xoá nghĩa hoặc tiến độ.
- Xoá chủ đề riêng: chỉ xoá chủ đề và các liên kết. Nghĩa không còn chủ đề xuất hiện ở Chưa phân loại.
- Xoá khỏi toàn bộ kho học: thao tác riêng cho nghĩa chưa phân loại; có thể xoá tiến độ theo lựa chọn người dùng.
- Quản trị bộ từ hệ thống: `set_catalog_topics` thay các liên kết hệ thống, giữ liên kết riêng và tiến độ.
- Duyệt bản nháp: `attach_reviewed_topic_meanings` lưu các mã nghĩa được duyệt, giữ tiến độ có sẵn.

Không gộp nghĩa tự động dựa vào bản dịch hoặc chuỗi chữ. Người dùng chọn nghĩa
đã có hoặc chủ động tạo nghĩa mới. Sửa cách diễn đạt giữ mã nghĩa; đổi sang ý nghĩa
khác phải tạo nghĩa mới. Các ghi chú cá nhân/phiên bản nội dung có thể bổ sung sau.

## Triển khai

Đã áp dụng lên Supabase ngày 27/09/2026 qua bản chuyển đổi
`20260927145045_vocabulary_topic_memberships_v1`. Kết nối đã có quyền ghi
(`read_only=false`: tắt chế độ chỉ đọc).

Kết quả xác nhận: 150 từ, 195 nghĩa, 133 tiến độ; 195 liên kết chủ đề–nghĩa và
133 liên kết bộ sưu tập của người học. Không có nghĩa thiếu mã từ, liên kết cũ bị
bỏ sót hoặc tiến độ trùng. Mã kiểm tra toàn bộ tiến độ và danh sách mã nghĩa trước/sau
trùng khớp, xác nhận giữ nguyên các bản ghi tiến độ và mã nghĩa hiện có.

Đã kiểm tra trực tiếp với quyền người dùng đã đăng nhập: thêm cùng nghĩa vào chủ đề
mới, lưu lặp và gỡ liên kết đều giữ nguyên toàn bộ tiến độ. Mọi thay đổi thử nghiệm
nằm trong giao dịch được hoàn tác, không để lại chủ đề thử hoặc thay đổi dữ liệu học.

Các bước bên dưới dành cho môi trường khác hoặc khi cần chạy lại tệp chuyển đổi:

1. Chạy toàn bộ `vocabulary_topic_memberships.sql` trong trình chạy truy vấn Supabase.
   Tệp có giao dịch bao ngoài: một lỗi sẽ huỷ toàn bộ thay đổi của lần chạy.
2. Kiểm tra số bản ghi `vocab_catalog` và `user_vocabulary` trước/sau phải không đổi.
   Khi rà trước chuyển đổi: 195 nghĩa, 133 bản ghi tiến độ. Số này có thể tăng nếu có người dùng học/thêm từ.
3. Phát hành mã ứng dụng đã cập nhật sau khi chuyển đổi thành công.
4. Truy vấn xác nhận:

```sql
select count(*) as meanings, count(distinct word_id) as words from public.vocab_catalog;
select count(*) as progress_rows from public.user_vocabulary;
select count(*) as catalog_memberships from public.topic_vocab;
select count(*) as selected_memberships from public.user_topic_vocab;
select user_id, vocab_id, count(*) from public.user_vocabulary
group by user_id, vocab_id having count(*) > 1;
```

Tệp không xoá nghĩa, tiến độ hay lượt trả lời. Việc chuyển liên kết cũ chỉ chạy
một lần, có dấu mốc trong `vocabulary_structure_migrations`; chạy lại không phục hồi
những chủ đề người dùng đã gỡ. Giữ `vocab_catalog.topic_id` để đọc dữ liệu cũ/bản nháp;
các ứng dụng mới không dùng cột này làm danh sách chủ đề. Máy khách cũ chỉ biết một
chủ đề; cần cập nhật máy khách để thêm/gỡ bộ sưu tập theo cấu trúc mới.

Ràng buộc tên chủ đề chuyển sang phạm vi từng chủ sở hữu cho chủ đề riêng, phạm vi
toàn hệ thống cho chủ đề công khai. Gỡ chính sách nguyên mẫu cho phép mọi người thấy
mọi chủ đề riêng. Quyền truy cập các bảng mới được giới hạn theo người sở hữu/nội dung
công khai; thao tác ghi thông qua các hàm đã kiểm tra quyền.

Đồng thời sửa giới hạn cấp 0–6 thành cấp không âm để lịch ôn 30/60/120/... ngày đã có
có thể tiếp tục sau cấp 6. Đây chưa phải thuật toán cá nhân hoá Extra.

## Kiểm thử

Khi lấy chủ đề cũ trực tiếp từ `vocab_catalog`, các truy vấn ứng dụng phải dùng
`topics!vocab_catalog_topic_id_fkey(...)` để chỉ rõ liên kết qua `topic_id`.
Sau khi có `topic_vocab`, cách viết `topics(...)` trở nên không rõ đang chọn liên kết
cũ hay liên kết nhiều chủ đề, gây lỗi PGRST201. Các truy vấn iPhone và web đã được sửa
đồng bộ; tên trường trả về vẫn là `topics` để giữ tương thích bộ đọc dữ liệu.

```sh
node supabase/tests/vocabulary_topic_memberships_test.mjs /tmp/omninary-streak-pg
npm --prefix admin-web run build
python3 supabase/tests/vocabulary_rest_relationships_test.py
```

Kiểm tra truy vấn trực tiếp trên Supabase lấy nguyên chuỗi truy vấn trong mã ứng dụng
và web: tái hiện PGRST201 khi bỏ chỉ định liên kết, rồi xác nhận truy vấn đã sửa trả
thành công. Kiểm tra này chỉ đọc, dùng khoá công khai của ứng dụng, không in dữ liệu
người học. Có thể đặt `SUPABASE_TEST_ACCESS_TOKEN` để kiểm tra với tài khoản đã đăng nhập.

Bộ kiểm thử dùng PostgreSQL riêng, không kết nối Supabase; kiểm tra bảo toàn tiến độ,
liên kết nhiều chủ đề, quyền đọc/ghi, xoá chủ đề, chạy lại chuyển đổi và cấp trên 6.
Các kiểm thử Swift trong `OmninaryTests` kiểm tra cùng một nghĩa thuộc hai chủ đề,
loại trùng trong phiên học và định danh ổn định khi sửa nội dung.
