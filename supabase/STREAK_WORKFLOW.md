# Quy trình giữ chuỗi thống nhất

## Áp dụng lên Supabase

Chạy **toàn bộ `omninary_unified.sql` một lần** trong trình chạy SQL (Structured Query Language – ngôn ngữ truy vấn có cấu trúc) của dự án Supabase hiện tại, rồi sử dụng phiên bản ứng dụng mới.

Tệp này bổ sung các cột cần thiết, lịch sử đóng băng và ghi đè các hàm sử dụng vật phẩm, làm mới chuỗi, ghi nhận hoạt động, hoàn thành phiên từ vựng và ghi nhận kết quả học. Có thể chạy lại; không xóa tài khoản, số dư điểm hoặc lịch sử học. Toàn bộ thay đổi nằm trong một giao dịch: nếu có lỗi, giao dịch không được áp dụng.

Tệp yêu cầu các bảng nền hiện có của ứng dụng (`profiles`, `user_stats`, `activity_logs`, `user_vocabulary`) và hàm kiểm tra quản trị viên `is_admin()`. Đây là bản cập nhật cho dự án hiện tại, không phải tệp tạo một dự án Supabase trống.

Không cần chạy lại `streak_restore_window.sql` hoặc `fix_streak_refresh_null_freeze.sql`; hai tệp này đã ngừng ghi đè các hàm chuỗi. Các nguồn riêng dùng để bảo trì nằm trong `streak_workflow.sql`, `omni_item_catalog.sql`, `vocabulary_learning_atomic_flow.sql` và `extra_v1_learning_telemetry.sql`. Sau khi chỉnh nguồn, chạy `python3 supabase/build_unified.py` để tạo lại tệp giao cho Supabase.

## Quy tắc đã triển khai

- Mọi ngày và mốc 0 giờ đều theo giờ Việt Nam. Chỉ máy chủ ghi nhận số ngày chuỗi, số điểm và quyền dùng vật phẩm.
- Lần hoàn thành phiên đầu tiên trong ngày tăng chuỗi một lần, lưu lại chuỗi mới và về trang chủ xem hiệu ứng. Các phiên sau về trang học. Học từ vựng, luyện nghe và luyện nói dùng chung một hàm ghi nhận ngày học; luyện nghe và nói chỉ ghi nhận khi hoàn thành cả phiên.
- Mở lại ứng dụng hoặc làm mới dữ liệu không chạy hiệu ứng. Sự kiện hiệu ứng chỉ tồn tại trong bộ nhớ khi thao tác vừa thành công, được nhận một lần và bị hủy nếu rời trang.
- Hiệu ứng giữ chuỗi: gỡ băng nếu có → thắp sáng thẻ chuỗi và năng lượng → nhảy số → biến đổi lửa nếu đạt mốc → thêm năng lượng, đầy thanh và đổi mốc nếu cần → đánh dấu lịch đã học.
- Đóng băng cần chuỗi lớn hơn 0 và chưa học hôm nay; bảo vệ tới trước 0 giờ ngày mai, không tăng chuỗi. Lịch sử đóng băng được giữ riêng. Học cùng ngày thay dấu băng bằng dấu đã học.
- Mỗi lần đóng băng cách nhau ít nhất 7 ngày và phải có một phiên học sau lần đóng băng trước. Không được đóng băng trong ngày vừa cứu chuỗi.
- Ngày đóng băng kéo dài mốc bảo vệ một ngày. Ví dụ học ngày 24, đóng băng ngày 25, bỏ học ngày 26: mất chuỗi lúc 0 giờ ngày 27, được cứu tới trước 0 giờ ngày 28 nếu còn quyền gói đặc biệt.
- Lịch đánh dấu đỏ ngày bỏ học đã được Người giữ lửa cứu, có biểu tượng lửa và chú giải “Đã cứu”. Dấu đỏ xuất hiện sau thao tác cứu thành công, được lưu riêng và không tính là ngày đã học. Khi mở lại ứng dụng, dấu đỏ hiển thị ngay, không phát lại hiệu ứng.
- Người giữ lửa cần quyền gói đặc biệt còn hiệu lực, chuỗi 0, chuỗi lưu lớn hơn 0 và còn hạn cứu; tốn 1.000 điểm. Cứu xong chuỗi trở về x màu xám, chuỗi lưu bằng 0. Phải học trước 0 giờ ngày mai để tăng thành x+1 và lưu lại x+1.
- Không học sau khi cứu hoặc không cứu trước khi hết hạn: cả hai số về 0, không được cứu tiếp. Mở ứng dụng muộn không gia hạn cứu chuỗi.
- Khi chuỗi cũ còn hạn cứu, trước khi học có lựa chọn cứu trước, bắt đầu chuỗi mới hoặc để sau. Hoàn thành phiên trước khi cứu sẽ bắt đầu lại từ 1 và mất quyền cứu chuỗi cũ.

## Thử trên phần mô phỏng trong Cài đặt

Phần mô phỏng có đồng hồ và lịch riêng, không dùng điểm hoặc ghi chuỗi thật. Cần tắt mô phỏng trước khi vào một phiên học thật.

1. Nhập **9 ngày**: lửa xám ngay, không hiệu ứng. Bấm **Giữ chuỗi**: xem chuyển mốc 9 → 10. Bấm lại **Giữ chuỗi**: chuỗi không tăng và chuyển về trang học.
2. Nhập **3 ngày**, bấm **Mùa đông không lạnh**: xem đóng băng và bộ đếm tới 0 giờ. Bấm **Qua ngày mới**: băng tan, vẫn 3 xám. Bấm dùng băng nữa: bị từ chối. Bấm **Giữ chuỗi**: lên 4.
3. Nhập **3 ngày**, bấm **Qua ngày mới**: về 0, lưu 3 và mở hạn cứu nếu đang mô phỏng gói đặc biệt. Bấm **Người giữ lửa**: về 3 xám, lưu 0. Dùng băng bị từ chối. Qua ngày mới mà không học: cả hai về 0, không cứu tiếp.
4. Làm lại bước cứu nhưng sau khi cứu bấm **Giữ chuỗi**: lên 4 sáng, lưu 4.
5. Nhập **3 ngày**, dùng băng, qua ngày mới hai lần: chuỗi mất sau ngày được bảo vệ, mở hạn cứu mới. Bấm **Hết hạn cứu chuỗi**: chuỗi lưu về 0.
6. Khi đang có hạn cứu, bấm **Giữ chuỗi**: kiểm tra hộp lựa chọn cứu trước hoặc bắt đầu chuỗi mới.
7. Thử các nút mốc **10 / 30 / 100 / 200 / 300**. Nút **Qua 7 ngày** giúp thử điều kiện hết thời gian chờ; vẫn phải có một phiên học trước khi dùng băng lại.
8. Bấm **Đưa toàn app về dữ liệu thật** để kết thúc mô phỏng và tải lại trạng thái từ máy chủ.

## Kiểm tra tự động

- `supabase/tests/streak_workflow_test.mjs`: chạy các hàm thật trong PostgreSQL tạm, gồm cài đặt lại, thời hạn, chi phí, đóng băng, cứu chuỗi, ghi nhận phiên trùng, đường gọi phiên học thực tế và quyền truy cập.
- `scripts/streak_simulator_check.swift`: kiểm tra mô phỏng bằng chính mã nguồn ứng dụng, gồm các nhánh trạng thái và sự kiện hiệu ứng chỉ nhận một lần.

Hai kiểm tra trên không kết nối với Supabase thật. Bản biên dịch ứng dụng được kiểm tra bằng Xcode; vẫn nên chạy các bước giao diện trên thiết bị trước khi phát hành.

### Thử dấu đỏ ngày được cứu

Đặt chuỗi 9 ngày màu xám, qua ngày mới để mất chuỗi, rồi dùng Người giữ lửa: ngày bỏ học hôm trước được tô đỏ. Hoàn thành phiên mô phỏng hôm nay để lên 10: hôm nay được đánh dấu đã học, ngày hôm trước vẫn đỏ. Thử cả khi ngày cứu là ngày 1 của tháng mới; lịch hiển thị tháng chứa ngày bị bỏ học để nhìn thấy dấu đỏ. Những lần cứu từ trước khi có bảng lịch sử mới không được suy đoán để tự tô lại.
