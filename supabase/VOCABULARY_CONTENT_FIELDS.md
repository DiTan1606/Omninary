# Thuộc tính nội dung từ vựng

Cập nhật 12/10/2026. Mỗi `vocab_catalog.id` là một đơn vị học độc lập. Có **16 thuộc tính nội dung**: 9 thuộc tính chính và 7 thuộc tính bổ sung. Mã từ, người sở hữu, liên kết bộ từ và tiến độ nằm ngoài nhóm thuộc tính này. Cùng một mã từ trong nhiều bộ từ vẫn có một tiến độ cho mỗi người học.

| Nhóm | Thuộc tính | Quy ước |
|---|---|---|
| Chính | `word` | Một cách viết tiếng Anh, có thể là từ hoặc cụm từ |
| Chính | `cefr` | CEFR (Common European Framework of Reference for Languages – Khung tham chiếu trình độ ngôn ngữ chung châu Âu), theo cách dùng của bản ghi |
| Chính | `ipa` | IPA (International Phonetic Alphabet – Bảng ký hiệu ngữ âm quốc tế), một phiên âm chính |
| Chính | `word_form` | Một từ loại/dạng mục học; thành ngữ dùng giá trị `idioms` |
| Chính | `e_meaning` | Một định nghĩa tiếng Anh |
| Chính | `ev_meaning` | Bản dịch tiếng Việt tương ứng của định nghĩa |
| Chính | `v_meaning` | Một diễn giải nghĩa ngắn, thống nhất cách dùng |
| Chính | `e_example` | Một câu ví dụ tiếng Anh hoàn chỉnh |
| Chính | `v_example` | Bản dịch tương ứng của câu ví dụ |
| Bổ sung | `word_family` | Họ từ, có thể kèm từ loại và diễn giải |
| Bổ sung | `synonymous` | Từ/cụm đồng nghĩa theo đúng cách dùng |
| Bổ sung | `antonym` | Từ/cụm trái nghĩa theo đúng cách dùng |
| Bổ sung | `collocation` | Cụm từ thường đi cùng |
| Bổ sung | `formula` | Mẫu cấu trúc/cách kết hợp |
| Bổ sung | `note` | Ghi chú cách dùng, phân biệt từ, lỗi thường gặp |
| Bổ sung | `bonus` | Thông tin mở rộng |

Tất cả đều lưu dưới dạng `text` (văn bản). Chín thuộc tính chính bắt buộc là chuỗi không trống; các thuộc tính bổ sung có thể trống hoặc chứa nhiều giá trị, phân tách bằng dấu `;`. Dấu phẩy trong một diễn giải không tạo giá trị mới. Ví dụ: `maker (n): người tạo ra; making (n): sự tạo ra`. Ứng dụng hiển thị mỗi phần không trống trên một thẻ riêng; khi lưu, bỏ khoảng trắng quanh từng phần và bỏ phần rỗng. Không dùng dấu `;` làm dấu câu bên trong một giá trị cần giữ nguyên trên cùng thẻ.

## Thành ngữ và số thứ tự

Thuộc tính `idioms` đã được bỏ khỏi danh mục, bản chụp gửi duyệt, mẫu dữ liệu, biểu mẫu, truy vấn và bộ xuất bảng tính. Một thành ngữ như `go Dutch` (chia đều tiền) là bản ghi riêng với `word_form = 'idioms'`; không gắn vào một từ chỉ vì có cùng cách viết một thành phần.

`STT CŨ` và `STT MỚI` chỉ dùng để đối chiếu nguồn. Bộ nhập không ánh xạ hai cột này thành mã từ hoặc tiến độ. Cột thành ngữ của bảng tính cũ cũng bị bỏ qua; cần tạo riêng những thành ngữ muốn học trước khi nhập.

## Quy tắc lưu và phạm vi bảo vệ

Chạy `vocabulary_content_fields_v3.sql` trước `vocabulary_content_contract_v4.sql`. Bản cập nhật thứ tư áp dụng lên Supabase Ditanary ngày 12/10/2026:

- Bỏ cột thành ngữ ở hai bảng. Bản cập nhật dừng nếu cột cũ còn nội dung, tránh mất dữ liệu chưa chuyển thành mục độc lập.
- Hàm tạo và cơ chế kiểm tra trước khi ghi yêu cầu đủ 9 thuộc tính chính, chuẩn hoá dấu `;` trong 7 thuộc tính bổ sung; câu ví dụ chỉ có dấu lửng bị từ chối.
- Hàm tạo chỉ nhận thuộc tính dạng chuỗi văn bản, không nhận mảng/đối tượng làm nội dung. Kiểm tra bắt buộc không thể tự xác nhận định nghĩa đúng hay một câu chứa một cách dùng duy nhất; phần ngữ nghĩa vẫn cần biên soạn và duyệt.
- Cả ứng dụng iPhone, trang quản trị và bộ nhập từ bảng tính cùng kiểm tra tính đầy đủ. Nhận xét dạng xuống dòng rồi `(Nhận xét ưu tiên 1/2/3: ...)` phải được xử lý và xoá trước khi nhập; nhận xét rà dữ liệu không trở thành nội dung học.
- Quyền đăng nhập, quyền quản trị khi tạo nội dung hệ thống và kiểm tra quyền vào bộ từ được giữ nguyên.

**Dữ liệu cũ:** 196 bản ghi danh mục, 137 tiến độ và các liên kết không thay đổi. Có 4 bản ghi danh mục cũ thiếu câu ví dụ Anh/Việt; ràng buộc chưa kiểm tra toàn bộ dữ liệu cũ để giữ nguyên chúng. Mọi lần tạo hoặc cập nhật nội dung sau này vẫn phải đầy đủ. Cần bổ sung các câu ví dụ cũ trước khi xác nhận toàn bộ danh mục đạt chuẩn. Bộ thực nghiệm trong bảng tính chưa được nhập vào Supabase.

## Xác nhận

- Kiểm tra cơ sở dữ liệu: `node supabase/tests/vocabulary_content_contract_test.mjs <thư mục PGlite>`; PGlite (PostgreSQL Lite – cơ sở dữ liệu PostgreSQL cục bộ gọn nhẹ) kiểm tra quyền người dùng, ghi trực tiếp, hàm tạo, thuộc tính bắt buộc, dấu phân cách, bảo vệ nhận xét, giữ tiến độ và chạy lại bản cập nhật.
- Kiểm tra bộ nhập: `node admin-web/tests/vocabulary-content-import.test.mjs`; nguồn cũ đủ 9 thuộc tính vẫn nhập được, nguồn thiếu thuộc tính được báo lỗi; ghi chú và thông tin mở rộng tách riêng.
- Bản chạy trên trình duyệt và ứng dụng cho trình mô phỏng iPhone biên dịch thành công. Chưa xác nhận toàn bộ thao tác trên thiết bị thật.
