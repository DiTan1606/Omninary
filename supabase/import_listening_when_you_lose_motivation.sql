-- Import listening lesson: When You Lose Motivation
-- Listening series: Stories of Life
-- Generated from Data/listening/when_you_lose_motivation/manifest.csv
-- Expected storage bucket: listening-audio
-- Expected object prefix: lessons/when_you_lose_motivation

begin;

with upsert_series as (
  insert into public.listening_series (
    slug,
    title,
    vi_title,
    is_published
  )
  values (
    'stories-of-life',
    'Stories of Life',
    'Những câu chuyện cuộc sống',
    true
  )
  on conflict (slug) do update
  set
    title = excluded.title,
    vi_title = excluded.vi_title,
    is_published = excluded.is_published
  returning id
),
upsert_lesson as (
  insert into public.listening_lessons (
    series_id,
    slug,
    source_id,
    title,
    vi_title,
    cefr,
    description,
    is_published
  )
  values (
    (select id from upsert_series),
    'when_you_lose_motivation',
    '5',
    'When You Lose Motivation',
    'Khi bạn mất động lực',
    'B1',
    'Listening dictation lesson generated from Omninary source material.',
    true
  )
  on conflict (slug) do update
  set
    series_id = excluded.series_id,
    source_id = excluded.source_id,
    title = excluded.title,
    vi_title = excluded.vi_title,
    cefr = excluded.cefr,
    description = excluded.description,
    is_published = excluded.is_published
  returning id
),
segment_data (
  order_index,
  english_text,
  vietnamese_text,
  ipa,
  audio_path,
  duration_seconds,
  word_count
) as (
  values
    (1, 'There will be moments when you feel you''ve lost your motivation and don''t want to do anything.', 'Sẽ có những lúc bạn cảm thấy mình đã mất động lực và chẳng muốn làm bất cứ điều gì.', '/ðɛr wɪl bi ˈmoʊmənts wɪn ju fil juv lɔst jʊr ˌmoʊtəˈveɪʃən ənd doʊnt wɔnt tɪ du ˈɛniˌθɪŋ./', 'lessons/when_you_lose_motivation/5_01_when_you_lose_motivation.mp3', 5.825, 17),
    (2, 'Even people who are successful in life and work fall into the state.', 'Ngay cả những người thành công trong cuộc sống và công việc cũng có lúc rơi vào trạng thái này.', '/ˈivɪn ˈpipəl hu ər səkˈsɛsfəl ɪn laɪf ənd wərk fɔl ˈɪntu ðə steɪt./', 'lessons/when_you_lose_motivation/5_02_when_you_lose_motivation.mp3', 5.068, 13),
    (3, 'However, let''s see how they deal with this "down" mentality that helps them move forward and achieve great things!', 'Tuy nhiên, hãy xem họ đối mặt với trạng thái tinh thần "đi xuống" này như thế nào và cách đó giúp họ tiến về phía trước, đạt được những điều tuyệt vời ra sao.', '/ˌhaʊˈɛvər, lɛts si haʊ ðeɪ dil wɪθ ðɪs daʊn mɛnˈtælɪti ðət hɛlps ðɛm muv ˈfɔrwərd ənd əˈʧiv greɪt θɪŋz!/', 'lessons/when_you_lose_motivation/5_03_when_you_lose_motivation.mp3', 7.784, 19),
    (4, 'Motivation is one of the master keys that will motivate you and keep you going every day.', 'Động lực là một trong những chiếc chìa khóa quan trọng sẽ thúc đẩy bạn và giúp bạn tiếp tục tiến bước mỗi ngày.', '/ˌmoʊtəˈveɪʃən ɪz wən əv ðə ˈmæstər kiz ðət wɪl ˈmoʊtəˌveɪt ju ənd kip ju goʊɪŋ ˈɛvəri deɪ./', 'lessons/when_you_lose_motivation/5_04_when_you_lose_motivation.mp3', 5.616, 17),
    (5, 'If you''re not motivated, you''ll tend to procrastinate about what has to be done.', 'Nếu không có động lực, bạn sẽ có xu hướng trì hoãn những việc cần làm.', '/ɪf jʊr nɑt ˈmoʊtəˌveɪtəd, jul tɛnd tɪ prəˈkræstəˌneɪt əˈbaʊt wət həz tɪ bi dən./', 'lessons/when_you_lose_motivation/5_05_when_you_lose_motivation.mp3', 5.538, 14),
    (6, 'In the end, you will feel depressed, helpless and give up on everything or completely give up on the project/work you are working on.', 'Cuối cùng, bạn sẽ cảm thấy chán nản, bất lực và từ bỏ mọi thứ hoặc hoàn toàn từ bỏ dự án hay công việc mình đang làm.', '/ɪn ðə ɛnd, ju wɪl fil dɪˈprɛst, ˈhɛlpləs ənd gɪv əp ɔn ˈɛvriˌθɪŋ ər kəmˈplitli gɪv əp ɔn ðə ˈprɑʤɛkt wərk ju ər ˈwərkɪŋ ɔn./', 'lessons/when_you_lose_motivation/5_06_when_you_lose_motivation.mp3', 8.568, 25),
    (7, 'So, the following solutions will be five great ways for you to overcome this terrible state.', 'Vì vậy, những giải pháp sau đây sẽ là năm cách tuyệt vời giúp bạn vượt qua trạng thái tồi tệ này.', '/soʊ, ðə ˈfɑloʊɪŋ səˈluʃənz wɪl bi faɪv greɪt weɪz fər ju tɪ ˈoʊvərˌkəm ðɪs ˈtɛrəbəl steɪt./', 'lessons/when_you_lose_motivation/5_07_when_you_lose_motivation.mp3', 7.001, 16),
    (8, 'Listen together!', 'Hãy cùng lắng nghe nhé!', '/ˈlɪsən təˈgɛðər!/', 'lessons/when_you_lose_motivation/5_08_when_you_lose_motivation.mp3', 1.567, 2),
    (9, 'One: Remember why you want to do it?', 'Một: Hãy nhớ lý do bạn muốn làm điều đó.', '/wən: rɪˈmɛmbər waɪ ju wɔnt tɪ du ɪt?/', 'lessons/when_you_lose_motivation/5_09_when_you_lose_motivation.mp3', 3.161, 8),
    (10, 'If you feel a lack of motivation when you want to write an essay, try to think about why you want to do it.', 'Nếu cảm thấy thiếu động lực khi muốn viết một bài luận, hãy thử nghĩ về lý do bạn muốn làm việc đó.', '/ɪf ju fil ə læk əv ˌmoʊtəˈveɪʃən wɪn ju wɔnt tɪ raɪt ən ˈɛˌseɪ, traɪ tɪ θɪŋk əˈbaʊt waɪ ju wɔnt tɪ du ɪt./', 'lessons/when_you_lose_motivation/5_10_when_you_lose_motivation.mp3', 7.654, 24),
    (11, 'Your reasons for doing something are the driving force behind all your actions.', 'Những lý do khiến bạn làm một việc chính là động lực đằng sau mọi hành động của bạn.', '/jʊr ˈrizənz fər duɪŋ ˈsəmθɪŋ ər ðə ˈdraɪvɪŋ fɔrs bɪˈhaɪnd ɔl jʊr ˈækʃənz./', 'lessons/when_you_lose_motivation/5_11_when_you_lose_motivation.mp3', 5.042, 13),
    (12, 'For example, why do people stop smoking?', 'Ví dụ, tại sao mọi người lại bỏ thuốc lá?', '/fər ɪgˈzæmpəl, waɪ du ˈpipəl stɑp ˈsmoʊkɪŋ?/', 'lessons/when_you_lose_motivation/5_12_when_you_lose_motivation.mp3', 3.683, 7),
    (13, 'Most people stop smoking because they have a powerful reason.', 'Hầu hết mọi người bỏ thuốc vì họ có một lý do đủ mạnh mẽ.', '/moʊst ˈpipəl stɑp ˈsmoʊkɪŋ bɪˈkəz ðeɪ hæv ə ˈpaʊərfəl ˈrizən./', 'lessons/when_you_lose_motivation/5_13_when_you_lose_motivation.mp3', 4.598, 10),
    (14, 'If they continue to smoke, they can suffer serious health problems that can affect their loved ones.', 'Nếu tiếp tục hút thuốc, họ có thể gặp những vấn đề sức khỏe nghiêm trọng, gây ảnh hưởng đến người thân yêu.', '/ɪf ðeɪ kənˈtɪnju tɪ smoʊk, ðeɪ kən ˈsəfər ˈsɪriəs hɛlθ ˈprɑbləmz ðət kən əˈfɛkt ðɛr ləvd wənz./', 'lessons/when_you_lose_motivation/5_14_when_you_lose_motivation.mp3', 6.217, 17),
    (15, 'So why do you do these jobs?', 'Vậy tại sao bạn lại làm những công việc này?', '/soʊ waɪ du ju du ðiz ʤɑbz?/', 'lessons/when_you_lose_motivation/5_15_when_you_lose_motivation.mp3', 2.952, 7),
    (16, 'Do you know why you want to achieve your goal?', 'Bạn có biết vì sao mình muốn đạt được mục tiêu không?', '/du ju noʊ waɪ ju wɔnt tɪ əˈʧiv jʊr goʊl?/', 'lessons/when_you_lose_motivation/5_16_when_you_lose_motivation.mp3', 3.265, 10),
    (17, 'Make sure your reasons are strong and realistic.', 'Hãy đảm bảo rằng lý do của bạn đủ mạnh mẽ và thực tế.', '/meɪk ʃʊr jʊr ˈrizənz ər strɔŋ ənd ˌriəˈlɪstɪk./', 'lessons/when_you_lose_motivation/5_17_when_you_lose_motivation.mp3', 3.448, 8),
    (18, 'When you feel unmotivated, think about why you want to do it.', 'Khi cảm thấy mất động lực, hãy nghĩ về lý do bạn muốn làm điều đó.', '/wɪn ju fil ənˈmoʊtəˌveɪtɪd, θɪŋk əˈbaʊt waɪ ju wɔnt tɪ du ɪt./', 'lessons/when_you_lose_motivation/5_18_when_you_lose_motivation.mp3', 4.728, 12),
    (19, 'Two: Visualize success if you do it and feel regret if you don''t.', 'Hai: Hãy hình dung thành công nếu bạn làm điều đó và cảm thấy hối tiếc nếu không làm.', '/tu: ˈvɪʒwəˌlaɪz səkˈsɛs ɪf ju du ɪt ənd fil rɪˈgrɛt ɪf ju doʊnt./', 'lessons/when_you_lose_motivation/5_19_when_you_lose_motivation.mp3', 5.642, 13),
    (20, 'Intuitive is a powerful tool that you have available and is completely free.', 'Trực giác là một công cụ mạnh mẽ mà bạn có sẵn và hoàn toàn miễn phí.', '/ˌɪnˈtuətɪv ɪz ə ˈpaʊərfəl tul ðət ju hæv əˈveɪləbəl ənd ɪz kəmˈplitli fri./', 'lessons/when_you_lose_motivation/5_20_when_you_lose_motivation.mp3', 5.016, 13),
    (21, 'You can think and imagine whatever, wherever and whenever you want.', 'Bạn có thể suy nghĩ và tưởng tượng bất cứ điều gì, ở bất cứ đâu và bất cứ khi nào bạn muốn.', '/ju kən θɪŋk ənd ˌɪˈmæʤən ˌwəˈtɛvər, wɛˈrɛvər ənd wɛˈnɛvər ju wɔnt./', 'lessons/when_you_lose_motivation/5_21_when_you_lose_motivation.mp3', 4.415, 11),
    (22, 'Try to imagine vividly, in as much detail as possible.', 'Hãy cố gắng tưởng tượng thật sống động và chi tiết nhất có thể.', '/traɪ tɪ ˌɪˈmæʤən ˈvɪvədli, ɪn ɛz məʧ ˈditeɪl ɛz ˈpɑsəbəl./', 'lessons/when_you_lose_motivation/5_22_when_you_lose_motivation.mp3', 4.023, 10),
    (23, 'For example, your dream is to drive a Mercedes-Benz.', 'Ví dụ, ước mơ của bạn là lái một chiếc Mercedes-Benz.', '/fər ɪgˈzæmpəl, jʊr drim ɪz tɪ draɪv ə mərˈseɪdiz bɛnz./', 'lessons/when_you_lose_motivation/5_23_when_you_lose_motivation.mp3', 3.631, 10),
    (24, 'Picture vividly that you are driving that car.', 'Hãy hình dung thật sống động rằng bạn đang lái chiếc xe đó.', '/ˈpɪkʧər ˈvɪvədli ðət ju ər ˈdraɪvɪŋ ðət kɑr./', 'lessons/when_you_lose_motivation/5_24_when_you_lose_motivation.mp3', 3.866, 8),
    (25, 'Imagine the model you want, the color, the feeling when you sit inside, the smell of the leather upholstery, feel the steering and hear the rumbling engine sound.', 'Hãy tưởng tượng mẫu xe bạn muốn, màu sắc, cảm giác khi ngồi bên trong, mùi da bọc ghế, cảm nhận vô lăng và nghe tiếng động cơ gầm vang.', '/ˌɪˈmæʤən ðə ˈmɑdəl ju wɔnt, ðə ˈkələr, ðə ˈfilɪŋ wɪn ju sɪt ˌɪnˈsaɪd, ðə smɛl əv ðə ˈlɛðər əpˈhoʊlstəri, fil ðə ˈstɪrɪŋ ənd hir ðə ˈrəmbəlɪŋ ˈɪnʤən saʊnd./', 'lessons/when_you_lose_motivation/5_25_when_you_lose_motivation.mp3', 10.527, 28),
    (26, 'The point is, when you imagine and visualize something in your mind, you will feel motivated to do it.', 'Điều cốt lõi là khi tưởng tượng và hình dung một điều trong tâm trí, bạn sẽ cảm thấy có động lực để thực hiện nó.', '/ðə pɔɪnt ɪz, wɪn ju ˌɪˈmæʤən ənd ˈvɪʒwəˌlaɪz ˈsəmθɪŋ ɪn jʊr maɪnd, ju wɪl fil ˈmoʊtəˌveɪtəd tɪ du ɪt./', 'lessons/when_you_lose_motivation/5_26_when_you_lose_motivation.mp3', 7.732, 19),
    (27, 'When you dream about the car you want, you will create an inner motivation that you will work to have money to buy a car.', 'Khi mơ về chiếc xe mình muốn, bạn sẽ tạo ra động lực từ bên trong để làm việc và có tiền mua xe.', '/wɪn ju drim əˈbaʊt ðə kɑr ju wɔnt, ju wɪl kriˈeɪt ən ˈɪnər ˌmoʊtəˈveɪʃən ðət ju wɪl wərk tɪ hæv ˈməni tɪ baɪ ə kɑr./', 'lessons/when_you_lose_motivation/5_27_when_you_lose_motivation.mp3', 8.202, 25),
    (28, 'Try doing this when you feel like procrastinating and don''t have any motivation.', 'Hãy thử cách này khi bạn muốn trì hoãn và không còn chút động lực nào.', '/traɪ duɪŋ ðɪs wɪn ju fil laɪk prəˈkræstəˌneɪtɪŋ ənd doʊnt hæv ˈɛni ˌmoʊtəˈveɪʃən./', 'lessons/when_you_lose_motivation/5_28_when_you_lose_motivation.mp3', 5.329, 13),
    (29, 'Three: Create a supportive environment.', 'Ba: Tạo một môi trường hỗ trợ.', '/θri: kriˈeɪt ə səˈpɔrtɪv ɪnˈvaɪrənmənt./', 'lessons/when_you_lose_motivation/5_29_when_you_lose_motivation.mp3', 3.109, 5),
    (30, 'Did you know your surroundings can greatly affect your mood?', 'Bạn có biết môi trường xung quanh có thể ảnh hưởng rất lớn đến tâm trạng của mình không?', '/dɪd ju noʊ jʊr sərˈaʊndɪŋz kən ˈgreɪtli əˈfɛkt jʊr mud?/', 'lessons/when_you_lose_motivation/5_30_when_you_lose_motivation.mp3', 4.702, 10),
    (31, 'Tell me, how do you feel when you have a wonderful stay in a most luxurious resort?', 'Hãy thử nghĩ xem, bạn cảm thấy thế nào khi có một kỳ nghỉ tuyệt vời tại một khu nghỉ dưỡng sang trọng bậc nhất?', '/tɛl mi, haʊ du ju fil wɪn ju hæv ə ˈwəndərfəl steɪ ɪn ə moʊst ləgˈʒəriəs rɪˈzɔrt?/', 'lessons/when_you_lose_motivation/5_31_when_you_lose_motivation.mp3', 5.956, 17),
    (32, 'Do you feel more valuable and have more confidence?', 'Bạn có cảm thấy mình có giá trị hơn và tự tin hơn không?', '/du ju fil mɔr ˈvæljəbəl ənd hæv mɔr ˈkɑnfədɛns?/', 'lessons/when_you_lose_motivation/5_32_when_you_lose_motivation.mp3', 3.500, 9),
    (33, 'If you are always working with successful people who talk about business, you should also learn and join to talk about business topics.', 'Nếu thường xuyên làm việc với những người thành công hay nói về kinh doanh, bạn cũng nên học hỏi và cùng tham gia nói chuyện về các chủ đề kinh doanh.', '/ɪf ju ər ˈɔlˌweɪz ˈwərkɪŋ wɪθ səkˈsɛsfəl ˈpipəl hu tɔk əˈbaʊt ˈbɪznɪs, ju ʃʊd ˈɔlsoʊ lərn ənd ʤɔɪn tɪ tɔk əˈbaʊt ˈbɪznɪs ˈtɑpɪks./', 'lessons/when_you_lose_motivation/5_33_when_you_lose_motivation.mp3', 8.620, 23),
    (34, 'This is a good sign.', 'Đây là một dấu hiệu tốt.', '/ðɪs ɪz ə gʊd saɪn./', 'lessons/when_you_lose_motivation/5_34_when_you_lose_motivation.mp3', 2.142, 5),
    (35, 'It''s also a way to help you become active and use your surroundings to boost your energy levels.', 'Đây cũng là cách giúp bạn trở nên năng động và tận dụng môi trường xung quanh để nâng cao mức năng lượng.', '/ɪts ˈɔlsoʊ ə weɪ tɪ hɛlp ju bɪˈkəm ˈæktɪv ənd juz jʊr sərˈaʊndɪŋz tɪ bust jʊr ˈɛnərʤi ˈlɛvəlz./', 'lessons/when_you_lose_motivation/5_35_when_you_lose_motivation.mp3', 6.296, 18),
    (36, 'On the other hand, if you associate with negative people who are always spreading rumors and gossiping about others, you will also feel negative and unmotivated to work.', 'Mặt khác, nếu giao du với những người tiêu cực, luôn tung tin đồn và nói xấu người khác, bạn cũng sẽ cảm thấy tiêu cực và mất động lực làm việc.', '/ɔn ðə ˈəðər hænd, ɪf ju əˈsoʊʃiˌeɪt wɪθ ˈnɛgətɪv ˈpipəl hu ər ˈɔlˌweɪz ˈsprɛdɪŋ ˈrumərz ənd ˈgɑsəpɪŋ əˈbaʊt ˈəðərz, ju wɪl ˈɔlsoʊ fil ˈnɛgətɪv ənd ənˈmoʊtəˌveɪtɪd tɪ wərk./', 'lessons/when_you_lose_motivation/5_36_when_you_lose_motivation.mp3', 11.154, 28),
    (37, 'Sometimes you should also take care of your surroundings, like decorating your workspace, making it a place that makes you want to be there and try.', 'Đôi khi bạn cũng nên chăm chút môi trường xung quanh, như trang trí nơi làm việc thành một nơi khiến bạn muốn ở đó và nỗ lực.', '/ˈsəmˌtaɪmz ju ʃʊd ˈɔlsoʊ teɪk kɛr əv jʊr sərˈaʊndɪŋz, laɪk ˈdɛkərˌeɪtɪŋ jʊr ˈwɝkˌspeɪs, ˈmeɪkɪŋ ɪt ə pleɪs ðət meɪks ju wɔnt tɪ bi ðɛr ənd traɪ./', 'lessons/when_you_lose_motivation/5_37_when_you_lose_motivation.mp3', 9.639, 26),
    (38, 'Remember, your surroundings are very important and it can affect you.', 'Hãy nhớ rằng môi trường xung quanh rất quan trọng và nó có thể ảnh hưởng đến bạn.', '/rɪˈmɛmbər, jʊr sərˈaʊndɪŋz ər ˈvɛri ˌɪmˈpɔrtənt ənd ɪt kən əˈfɛkt ju./', 'lessons/when_you_lose_motivation/5_38_when_you_lose_motivation.mp3', 5.042, 11),
    (39, 'So, change the surroundings to motivate yourself.', 'Vì vậy, hãy thay đổi môi trường xung quanh để tạo động lực cho chính mình.', '/soʊ, ʧeɪnʤ ðə sərˈaʊndɪŋz tɪ ˈmoʊtəˌveɪt ˈjɔrsɛlf./', 'lessons/when_you_lose_motivation/5_39_when_you_lose_motivation.mp3', 3.944, 7),
    (40, 'Four: Dream big, start small and act now.', 'Bốn: Ước mơ lớn, bắt đầu nhỏ và hành động ngay.', '/fɔr: drim bɪg, stɑrt smɔl ənd ækt naʊ./', 'lessons/when_you_lose_motivation/5_40_when_you_lose_motivation.mp3', 4.937, 8),
    (41, 'This is a powerful principle if you apply it to your life.', 'Đây là một nguyên tắc mạnh mẽ nếu bạn áp dụng nó vào cuộc sống.', '/ðɪs ɪz ə ˈpaʊərfəl ˈprɪnsəpəl ɪf ju əˈplaɪ ɪt tɪ jʊr laɪf./', 'lessons/when_you_lose_motivation/5_41_when_you_lose_motivation.mp3', 4.310, 12),
    (42, 'When you dream, you have to dream big so that your dreams can inspire you.', 'Khi mơ ước, hãy dám mơ lớn để những ước mơ ấy có thể truyền cảm hứng cho bạn.', '/wɪn ju drim, ju hæv tɪ drim bɪg soʊ ðət jʊr drimz kən ˌɪnˈspaɪr ju./', 'lessons/when_you_lose_motivation/5_42_when_you_lose_motivation.mp3', 5.512, 15),
    (43, 'However, when you start, you have to start small because this will make it a habit so that you automatically take constant action every day.', 'Tuy nhiên, khi bắt đầu, bạn cần bắt đầu từ việc nhỏ vì điều này sẽ biến nó thành thói quen để bạn tự động hành động đều đặn mỗi ngày.', '/ˌhaʊˈɛvər, wɪn ju stɑrt, ju hæv tɪ stɑrt smɔl bɪˈkəz ðɪs wɪl meɪk ɪt ə ˈhæbət soʊ ðət ju ˌɔtəˈmætɪkli teɪk ˈkɑnstənt ˈækʃən ˈɛvəri deɪ./', 'lessons/when_you_lose_motivation/5_43_when_you_lose_motivation.mp3', 9.456, 25),
    (44, 'When your motivation is lost, start small, take the smallest steps, and develop from there.', 'Khi mất động lực, hãy bắt đầu từ việc nhỏ, thực hiện những bước nhỏ nhất rồi phát triển dần từ đó.', '/wɪn jʊr ˌmoʊtəˈveɪʃən ɪz lɔst, stɑrt smɔl, teɪk ðə ˈsmɔləst stɛps, ənd dɪˈvɛləp frəm ðɛr./', 'lessons/when_you_lose_motivation/5_44_when_you_lose_motivation.mp3', 7.549, 15),
    (45, 'For example, if you want to exercise and work out five days a week, try to plan and start slowly.', 'Ví dụ, nếu muốn tập thể dục năm ngày mỗi tuần, hãy thử lập kế hoạch và bắt đầu từ từ.', '/fər ɪgˈzæmpəl, ɪf ju wɔnt tɪ ˈɛksərˌsaɪz ənd wərk aʊt faɪv deɪz ə wik, traɪ tɪ plæn ənd stɑrt ˈsloʊli./', 'lessons/when_you_lose_motivation/5_45_when_you_lose_motivation.mp3', 7.680, 20),
    (46, 'Even if it''s just five minutes a day, commit to doing it right and just do it.', 'Dù chỉ là năm phút mỗi ngày, hãy cam kết thực hiện nghiêm túc và bắt tay vào làm.', '/ˈivɪn ɪf ɪts ʤɪst faɪv ˈmɪnəts ə deɪ, kəˈmɪt tɪ duɪŋ ɪt raɪt ənd ʤɪst du ɪt./', 'lessons/when_you_lose_motivation/5_46_when_you_lose_motivation.mp3', 5.878, 17),
    (47, 'Once you get motivated, you will get more motivated and go to higher levels.', 'Khi đã có động lực, bạn sẽ có thêm động lực và tiến lên những cấp độ cao hơn.', '/wəns ju gɪt ˈmoʊtəˌveɪtəd, ju wɪl gɪt mɔr ˈmoʊtəˌveɪtəd ənd goʊ tɪ haɪər ˈlɛvəlz./', 'lessons/when_you_lose_motivation/5_47_when_you_lose_motivation.mp3', 4.989, 14),
    (48, 'Five: Take a rest.', 'Năm: Hãy nghỉ ngơi.', '/faɪv: teɪk ə rɛst./', 'lessons/when_you_lose_motivation/5_48_when_you_lose_motivation.mp3', 2.952, 4),
    (49, 'Sometimes you just want to rest.', 'Đôi khi bạn chỉ muốn nghỉ ngơi.', '/ˈsəmˌtaɪmz ju ʤɪst wɔnt tɪ rɛst./', 'lessons/when_you_lose_motivation/5_49_when_you_lose_motivation.mp3', 3.030, 6),
    (50, 'Remember, success is not a destination, it is a journey that you need to go through a long time.', 'Hãy nhớ rằng thành công không phải là đích đến; đó là một hành trình dài.', '/rɪˈmɛmbər, səkˈsɛs ɪz nɑt ə ˌdɛstɪˈneɪʃən, ɪt ɪz ə ˈʤərni ðət ju nid tɪ goʊ θru ə lɔŋ taɪm./', 'lessons/when_you_lose_motivation/5_50_when_you_lose_motivation.mp3', 6.792, 19),
    (51, 'This is not a sprint, but a marathon.', 'Đây không phải là một cuộc chạy nước rút mà là một cuộc chạy marathon.', '/ðɪs ɪz nɑt ə sprɪnt, bət ə ˈmɛrəˌθɑn./', 'lessons/when_you_lose_motivation/5_51_when_you_lose_motivation.mp3', 3.396, 8),
    (52, 'Many people mistake success as doing something great and success will come overnight.', 'Nhiều người lầm tưởng thành công là làm được điều gì đó lớn lao và nghĩ rằng nó sẽ đến chỉ sau một đêm.', '/ˈmɛni ˈpipəl mɪˈsteɪk səkˈsɛs ɛz duɪŋ ˈsəmθɪŋ greɪt ənd səkˈsɛs wɪl kəm ˈoʊvərˈnaɪt./', 'lessons/when_you_lose_motivation/5_52_when_you_lose_motivation.mp3', 5.773, 13),
    (53, 'The truth is the opposite.', 'Sự thật hoàn toàn ngược lại.', '/ðə truθ ɪz ðə ˈɑpəzɪt./', 'lessons/when_you_lose_motivation/5_53_when_you_lose_motivation.mp3', 2.090, 5),
    (54, 'Almost all successful people who have achieved great results are able to do so because they persist long enough, they take consistent action and, of course, they never give up.', 'Hầu hết những người thành công đạt được kết quả lớn đều làm được như vậy vì họ kiên trì đủ lâu, hành động nhất quán và tất nhiên là không bao giờ bỏ cuộc.', '/ˈɔlˌmoʊst ɔl səkˈsɛsfəl ˈpipəl hu hæv əˈʧivd greɪt rɪˈzəlts ər ˈeɪbəl tɪ du soʊ bɪˈkəz ðeɪ pərˈsɪst lɔŋ ɪˈnəf, ðeɪ teɪk kənˈsɪstənt ˈækʃən ənd, əv kɔrs, ðeɪ ˈnɛvər gɪv əp./', 'lessons/when_you_lose_motivation/5_54_when_you_lose_motivation.mp3', 11.494, 30),
    (55, 'It is not something that can be created in a few days, not weeks, and not even months.', 'Thành công không phải là thứ có thể tạo nên trong vài ngày, vài tuần hay thậm chí vài tháng.', '/ɪt ɪz nɑt ˈsəmθɪŋ ðət kən bi kriˈeɪtɪd ɪn ə fju deɪz, nɑt wiks, ənd nɑt ˈivɪn mənθs./', 'lessons/when_you_lose_motivation/5_55_when_you_lose_motivation.mp3', 6.975, 18),
    (56, 'True success takes years to build.', 'Thành công thực sự cần nhiều năm để gây dựng.', '/tru səkˈsɛs teɪks jɪrz tɪ bɪld./', 'lessons/when_you_lose_motivation/5_56_when_you_lose_motivation.mp3', 2.952, 6),
    (57, 'So make sure you get enough rest and rest when you need it.', 'Vì vậy, hãy đảm bảo rằng bạn nghỉ ngơi đầy đủ và nghỉ khi cần.', '/soʊ meɪk ʃʊr ju gɪt ɪˈnəf rɛst ənd rɛst wɪn ju nid ɪt./', 'lessons/when_you_lose_motivation/5_57_when_you_lose_motivation.mp3', 3.892, 13),
    (58, 'You need to understand your abilities and to what extent you can do.', 'Bạn cần hiểu khả năng của mình và mức độ mình có thể làm được đến đâu.', '/ju nid tɪ ˌəndərˈstænd jʊr əˈbɪləˌtiz ənd tɪ wət ɪkˈstɛnt ju kən du./', 'lessons/when_you_lose_motivation/5_58_when_you_lose_motivation.mp3', 4.859, 13),
    (59, 'If you''re done with work, you can reward yourself by taking a rest.', 'Nếu đã hoàn thành công việc, bạn có thể tự thưởng cho mình bằng cách nghỉ ngơi.', '/ɪf jʊr dən wɪθ wərk, ju kən rɪˈwɔrd ˈjɔrsɛlf baɪ ˈteɪkɪŋ ə rɛst./', 'lessons/when_you_lose_motivation/5_59_when_you_lose_motivation.mp3', 4.911, 13),
    (60, 'You find that after resting, you will be more energetic, active and ready to "fight" again.', 'Bạn sẽ nhận ra rằng sau khi nghỉ ngơi, mình sẽ tràn đầy năng lượng hơn, năng động hơn và sẵn sàng "chiến đấu" trở lại.', '/ju faɪnd ðət ˈæftər ˈrɛstɪŋ, ju wɪl bi mɔr ˌɛnərˈʤɛtɪk, ˈæktɪv ənd ˈrɛdi tɪ faɪt əˈgɛn./', 'lessons/when_you_lose_motivation/5_60_when_you_lose_motivation.mp3', 6.269, 16)
)
insert into public.listening_segments (
  lesson_id,
  order_index,
  english_text,
  vietnamese_text,
  ipa,
  audio_path,
  duration_seconds,
  word_count
)
select
  upsert_lesson.id,
  segment_data.order_index,
  segment_data.english_text,
  segment_data.vietnamese_text,
  segment_data.ipa,
  segment_data.audio_path,
  segment_data.duration_seconds,
  segment_data.word_count
from upsert_lesson, segment_data
on conflict (lesson_id, order_index) do update
set
  english_text = excluded.english_text,
  vietnamese_text = excluded.vietnamese_text,
  ipa = excluded.ipa,
  audio_path = excluded.audio_path,
  duration_seconds = excluded.duration_seconds,
  word_count = excluded.word_count;


-- The lesson transcript changed. Existing attempts and scores no longer match
-- the expected answers, so reset only this lesson's listening progress.
delete from public.user_listening_progress
where segment_id in (
  select id
  from public.listening_segments
  where lesson_id = (
    select id
    from public.listening_lessons
    where slug = 'when_you_lose_motivation'
  )
);

update public.user_listening_lessons
set
  is_in_learning = false,
  completed_at = null,
  latest_score = 0,
  best_score = 0
where lesson_id = (
  select id
  from public.listening_lessons
  where slug = 'when_you_lose_motivation'
);


commit;

select
  l.slug,
  l.title,
  l.cefr,
  l.is_published,
  count(s.id) as segment_count
from public.listening_lessons l
left join public.listening_segments s on s.lesson_id = l.id
where l.slug = 'when_you_lose_motivation'
group by l.id;

select
  order_index,
  english_text,
  audio_path,
  duration_seconds,
  word_count
from public.listening_segments
where lesson_id = (
  select id
  from public.listening_lessons
  where slug = 'when_you_lose_motivation'
)
order by order_index;
