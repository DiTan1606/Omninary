-- Import listening lesson: Are You a Workaholic?
-- Listening series: I'm Mary
-- Generated from Data/listening/are_you_a_workaholic/manifest.csv
-- Expected storage bucket: listening-audio
-- Expected object prefix: lessons/are_you_a_workaholic

begin;

with upsert_series as (
  insert into public.listening_series (
    slug,
    title,
    vi_title,
    is_published
  )
  values (
    'im-mary',
    'I''m Mary',
    'Tôi là Mary',
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
    'are_you_a_workaholic',
    '95',
    'Are You a Workaholic?',
    'Bạn có phải là người nghiện công việc?',
    'B2',
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
    (1, 'In a culture that encourages ambition, to ensure a stable income, workers often devote all their time, including time for self-care, to handle an enormous workload.', 'Trong một nền văn hóa khuyến khích sự cầu tiến, để đảm bảo nguồn thu nhập ổn định, người lao động thường dành hết thời gian, bao gồm cả thời gian chăm sóc bản thân, để xử lý khối lượng công việc khổng lồ.', '/ɪn ə ˈkəlʧər ðət ɪnˈkərəʤəz æmˈbɪʃən, tɪ ɪnˈʃʊr ə ˈsteɪbəl ˈɪnˌkəm, ˈwərkərz ˈɔfən dɪˈvoʊt ɔl ðɛr taɪm, ˌɪnˈkludɪŋ taɪm fər ˌsɛlf ˈkɛr, tɪ ˈhændəl ən ɪˈnɔrmɪs ˈwərˌkloʊd./', 'lessons/are_you_a_workaholic/95_01_are_you_a_workaholic.mp3', 12.304, 27),
    (2, 'This phenomenon is particularly noticeable among the younger generation.', 'Hiện tượng này đặc biệt được nhận thấy rõ hơn ở giới trẻ.', '/ðɪs fəˈnɑməˌnɑn ɪz ˌpɑrˈtɪkjələrli ˈnoʊtəsəbəl əˈməŋ ðə ˈjəŋgər ˌʤɛnərˈeɪʃən./', 'lessons/are_you_a_workaholic/95_02_are_you_a_workaholic.mp3', 4.728, 9),
    (3, 'Many young people today prefer to be seen as "workaholics" because the feeling of being busy makes them feel like they are creating value for themselves and society.', 'Nhiều bạn trẻ hiện nay thích được xem là những "workaholic" (người nghiện công việc) bởi cảm giác bận rộn khiến họ thấy mình đang tạo ra giá trị cho bản thân và xã hội.', '/ˈmɛni jəŋ ˈpipəl təˈdeɪ prɪˈfər tɪ bi sin ɛz ˌwərkəˈhɑlɪks bɪˈkəz ðə ˈfilɪŋ əv biɪŋ ˈbɪzi meɪks ðɛm fil laɪk ðeɪ ər kriˈeɪtɪŋ ˈvælju fər ðɛmˈsɛlvz ənd soʊˈsaɪɪti./', 'lessons/are_you_a_workaholic/95_03_are_you_a_workaholic.mp3', 10.632, 28),
    (4, 'However, it’s time for young workers to pay attention to the warnings about their physical and mental health and reconsider their relationship with work.', 'Thế nhưng đã đến lúc người lao động trẻ cần chú ý đến những báo động về thể chất lẫn tinh thần, đồng thời nhìn nhận lại mối quan hệ giữa mình và công việc.', '/ˌhaʊˈɛvər, ɪts taɪm fər jəŋ ˈwərkərz tɪ peɪ əˈtɛnʃən tɪ ðə ˈwɔrnɪŋz əˈbaʊt ðɛr ˈfɪzɪkəl ənd ˈmɛntəl hɛlθ ənd ˌrikənˈsɪdər ðɛr riˈleɪʃənˌʃɪp wɪθ wərk./', 'lessons/are_you_a_workaholic/95_04_are_you_a_workaholic.mp3', 9.927, 24),
    (5, '"Workaholism" was first used in 1971 by psychologist Wayne Oates.', 'Cụm từ "nghiện công việc" lần đầu tiên được sử dụng vào năm 1971 bởi nhà tâm lý học Wayne Oates.', '/ˌwɝkəˈhɔˌlɪzəm wɑz fərst juzd ɪn ˌnaɪnˈtin ˌsɛvənˈti wən baɪ saɪˈkɑləʤəst weɪn oʊts./', 'lessons/are_you_a_workaholic/95_05_are_you_a_workaholic.mp3', 6.191, 9),
    (6, 'He defined it as a term describing a person with an uncontrollable need to work.', 'Ông định nghĩa đây là cụm từ mô tả tình trạng một người có nhu cầu làm việc ngoài kiểm soát.', '/hi dɪˈfaɪnd ɪt ɛz ə tərm dɪˈskraɪbɪŋ ə ˈpərsən wɪθ ən ˌənkənˈtroʊləbəl nid tɪ wərk./', 'lessons/are_you_a_workaholic/95_06_are_you_a_workaholic.mp3', 5.407, 15),
    (7, 'Workaholics always think of ways to spend as much time as possible on work.', 'Những "workaholic" luôn nghĩ cách để dành thời gian cho công việc nhiều nhất có thể.', '/ˌwərkəˈhɑlɪks ˈɔlˌweɪz θɪŋk əv weɪz tɪ spɛnd ɛz məʧ taɪm ɛz ˈpɑsəbəl ɔn wərk./', 'lessons/are_you_a_workaholic/95_07_are_you_a_workaholic.mp3', 5.512, 14),
    (8, 'They are constantly obsessed and feel guilty whenever they leave the workspace or take time to play or rest.', 'Họ luôn bị ám ảnh và mang cảm giác tội lỗi mỗi khi rời khỏi không gian làm việc hay dành thời gian vui chơi, nghỉ dưỡng.', '/ðeɪ ər ˈkɑnstəntli əbˈsɛst ənd fil ˈgɪlti wɛˈnɛvər ðeɪ liv ðə ˈwɝkˌspeɪs ər teɪk taɪm tɪ pleɪ ər rɛst./', 'lessons/are_you_a_workaholic/95_08_are_you_a_workaholic.mp3', 7.262, 19),
    (9, 'Workaholism is becoming increasingly common among young people, especially those who are perfectionists and pursue perfectionism.', 'Hội chứng nghiện công việc hiện nay ngày càng phổ biến hơn ở giới trẻ, đặc biệt là những người cầu toàn, theo đuổi chủ nghĩa hoàn hảo.', '/ˌwɝkəˈhɔˌlɪzəm ɪz bɪˈkəmɪŋ ˌɪnˈkrisɪŋgli ˈkɑmən əˈməŋ jəŋ ˈpipəl, əˈspɛʃəli ðoʊz hu ər pərˈfɛkʃənəsts ənd pərˈsu pərˈfɛkʃəˌnɪzəm./', 'lessons/are_you_a_workaholic/95_09_are_you_a_workaholic.mp3', 8.202, 16),
    (10, 'The feeling of physical, emotional, and mental exhaustion due to work has become all too normal for young people.', 'Cảm giác kiệt quệ về thể chất, cảm xúc và tinh thần vì công việc là điều đã trở nên quá đỗi bình thường đối với những người trẻ tuổi.', '/ðə ˈfilɪŋ əv ˈfɪzɪkəl, ˈiˌmoʊʃənəl, ənd ˈmɛntəl ɪgˈzɔsʧən du tɪ wərk həz bɪˈkəm ɔl tu ˈnɔrməl fər jəŋ ˈpipəl./', 'lessons/are_you_a_workaholic/95_10_are_you_a_workaholic.mp3', 6.844, 19),
    (11, 'We ignore the fact that we borrow hours of sleep to work extra hours and even forget about self-care.', 'Chúng ta phớt lờ sự thật rằng chúng ta mượn số giờ ngủ để làm thêm giờ, và thậm chí quên đi việc chăm sóc bản thân.', '/wi ˌɪgˈnɔr ðə fækt ðət wi ˈbɑˌroʊ aʊərz əv slip tɪ wərk ˈɛkstrə aʊərz ənd ˈivɪn fərˈgɛt əˈbaʊt ˌsɛlf ˈkɛr./', 'lessons/are_you_a_workaholic/95_11_are_you_a_workaholic.mp3', 7.732, 20),
    (12, 'This phenomenon leads to the consequence that nearly half of millennials have left their jobs due to mental health reasons, and diagnoses of depression are increasing at a faster rate among the younger generation than any other age group.', 'Hiện tượng này kéo theo hệ quả là gần một nửa số người thuộc thế hệ thiên niên kỷ đã rời bỏ công việc vì lý do sức khỏe tâm thần, và các chẩn đoán trầm cảm đang gia tăng với tốc độ nhanh hơn ở thế hệ thanh niên so với bất kỳ nhóm tuổi nào khác.', '/ðɪs fəˈnɑməˌnɑn lidz tɪ ðə ˈkɑnsəkwəns ðət ˈnɪrli hæf əv mɪˈlɛniəlz hæv lɛft ðɛr ʤɑbz du tɪ ˈmɛntəl hɛlθ ˈrizənz, ənd ˌdaɪəgˈnoʊsiz əv dɪˈprɛʃən ər ˌɪnˈkrisɪŋ æt ə ˈfæstər reɪt əˈməŋ ðə ˈjəŋgər ˌʤɛnərˈeɪʃən ðən ˈɛni ˈəðər eɪʤ grup./', 'lessons/are_you_a_workaholic/95_12_are_you_a_workaholic.mp3', 15.621, 39),
    (13, 'Taking on too many tasks simultaneously with high frequency, and prioritizing work above all else are signs of a workaholic.', 'Ôm đồm quá nhiều việc cùng lúc với tần suất cao, coi công việc là ưu tiên hàng đầu... đó là dấu hiệu của người nghiện việc.', '/ˈteɪkɪŋ ɔn tu ˈmɛni tæsks ˌsaɪməlˈteɪniəsli wɪθ haɪ ˈfrikwənsi, ənd praɪˈɔrəˌtaɪzɪŋ wərk əˈbəv ɔl ɛls ər saɪnz əv ə ˈwərkəˈhɑlɪk./', 'lessons/are_you_a_workaholic/95_13_are_you_a_workaholic.mp3', 9.143, 20),
    (14, 'Maintaining this habit causes many to fall into a state of stress and anxiety.', 'Duy trì thói quen này khiến nhiều người rơi vào trạng thái căng thẳng, lo âu.', '/meɪnˈteɪnɪŋ ðɪs ˈhæbət ˈkɔzɪz ˈmɛni tɪ fɔl ˈɪntu ə steɪt əv strɛs ənd æŋˈzaɪəti./', 'lessons/are_you_a_workaholic/95_14_are_you_a_workaholic.mp3', 5.381, 14),
    (15, 'Even if they aren’t working, they feel uncomfortable.', 'Thậm chí nếu không làm việc, họ sẽ có cảm giác khó chịu.', '/ˈivɪn ɪf ðeɪ ˈɑrənt ˈwərkɪŋ, ðeɪ fil ənˈkəmfərtəbəl./', 'lessons/are_you_a_workaholic/95_15_are_you_a_workaholic.mp3', 3.631, 8),
    (16, 'Those who suffer from workaholism are at risk of health problems such as insomnia, fatigue, stomach issues, anxiety, and depression.', 'Người mắc chứng nghiện việc có nguy cơ gặp vấn đề về sức khỏe như mất ngủ, mệt mỏi, vấn đề về dạ dày, lo âu và trầm cảm.', '/ðoʊz hu ˈsəfər frəm ˌwɝkəˈhɔˌlɪzəm ər æt rɪsk əv hɛlθ ˈprɑbləmz səʧ ɛz ˌɪnˈsɑmniə, fəˈtig, ˈstəmək ˈɪʃuz, æŋˈzaɪəti, ənd dɪˈprɛʃən./', 'lessons/are_you_a_workaholic/95_16_are_you_a_workaholic.mp3', 10.188, 20),
    (17, 'The lack of balance between work and personal life also leads to conflicts in relationships.', 'Sự thiếu cân bằng giữa công việc và cuộc sống cá nhân cũng dẫn đến mâu thuẫn trong các mối quan hệ.', '/ðə læk əv ˈbæləns bɪtˈwin wərk ənd ˈpərsɪnəl laɪf ˈɔlsoʊ lidz tɪ ˈkɑnflɪkts ɪn riˈleɪʃənˌʃɪps./', 'lessons/are_you_a_workaholic/95_17_are_you_a_workaholic.mp3', 6.348, 15),
    (18, 'Many cases result in having no time for oneself, family, children, or social relationships, gradually leading to loneliness.', 'Nhiều trường hợp không có thời gian cho bản thân, gia đình, con cái, các mối quan hệ xã hội, dần dần thành cô đơn.', '/ˈmɛni ˈkeɪsɪz rɪˈzəlt ɪn ˈhævɪŋ noʊ taɪm fər ˌwənˈsɛlf, ˈfæməli, ˈʧɪldrən, ər ˈsoʊʃəl riˈleɪʃənˌʃɪps, ˈgræʤuəli ˈlidɪŋ tɪ ˈloʊnlinəs./', 'lessons/are_you_a_workaholic/95_18_are_you_a_workaholic.mp3', 9.665, 18),
    (19, 'When they stop working, they feel alone and empty, so they continue to "work addictively" to relieve this, creating a vicious cycle.', 'Khi ngừng làm việc, họ cảm thấy đơn độc, trống rỗng, nên lại tiếp tục "nghiện việc" để giải tỏa, tạo thành vòng luẩn quẩn.', '/wɪn ðeɪ stɑp ˈwərkɪŋ, ðeɪ fil əˈloʊn ənd ˈɛmti, soʊ ðeɪ kənˈtɪnju tɪ wərk əˈdɪktɪvli tɪ rɪˈliv ðɪs, kriˈeɪtɪŋ ə ˈvɪʃəs ˈsaɪkəl./', 'lessons/are_you_a_workaholic/95_19_are_you_a_workaholic.mp3', 8.464, 22),
    (20, 'What solutions are there for workaholics?', 'Giải pháp nào cho những "workaholic"?', '/wət səˈluʃənz ər ðɛr fər ˌwərkəˈhɑlɪks?/', 'lessons/are_you_a_workaholic/95_20_are_you_a_workaholic.mp3', 3.709, 6),
    (21, 'Workaholism is entirely treatable, as long as you recognize your problem.', 'Chứng nghiện việc hoàn toàn có thể điều trị được, miễn là bạn nhận ra vấn đề của mình.', '/ˌwɝkəˈhɔˌlɪzəm ɪz ɪnˈtaɪərli ˈtritəbəl, ɛz lɔŋ ɛz ju ˈrɛkəgˌnaɪz jʊr ˈprɑbləm./', 'lessons/are_you_a_workaholic/95_21_are_you_a_workaholic.mp3', 5.068, 11),
    (22, 'Here are some methods you can implement to overcome workaholism and achieve a more balanced life.', 'Sau đây là một số phương pháp bạn có thể thực hiện để thoát khỏi chứng nghiện việc và có một cuộc sống cân bằng hơn.', '/hir ər səm ˈmɛθədz ju kən ˈɪmpləmənt tɪ ˈoʊvərˌkəm ˌwɝkəˈhɔˌlɪzəm ənd əˈʧiv ə mɔr ˈbælənst laɪf./', 'lessons/are_you_a_workaholic/95_22_are_you_a_workaholic.mp3', 6.191, 16),
    (23, 'Understand what is important.', 'Hiểu rõ điều gì là quan trọng.', '/ˌəndərˈstænd wət ɪz ˌɪmˈpɔrtənt./', 'lessons/are_you_a_workaholic/95_23_are_you_a_workaholic.mp3', 2.612, 4),
    (24, 'Thoroughly research your to-do list and major goals.', 'Nghiên cứu thật kỹ danh sách những việc phải làm và những mục tiêu lớn của bạn.', '/ˈθəroʊli ˈrisərʧ jʊr ˌtuˈdu lɪst ənd ˈmeɪʤər goʊlz./', 'lessons/are_you_a_workaholic/95_24_are_you_a_workaholic.mp3', 3.709, 9),
    (25, 'Some tasks are essential, and you must complete them yourself, but most others are not.', 'Một số việc là trọng yếu và bạn phải tự thực hiện, nhưng hầu hết những việc còn lại thì không.', '/səm tæsks ər ɛˈsɛnʃəl, ənd ju məst kəmˈplit ðɛm ˈjɔrsɛlf, bət moʊst ˈəðərz ər nɑt./', 'lessons/are_you_a_workaholic/95_25_are_you_a_workaholic.mp3', 5.538, 15),
    (26, 'Ask yourself: "How will this help my company?" and determine to eliminate unnecessary things.', 'Tự hỏi mình: "Việc này sẽ giúp gì cho công ty của tôi?" và hãy quyết tâm gạt bỏ những thứ không cần thiết.', '/æsk ˈjɔrsɛlf: haʊ wɪl ðɪs hɛlp maɪ ˈkəmpəˌni? ənd dɪˈtərmən tɪ ɪˈlɪməˌneɪt ənˈnɛsəˌsɛri θɪŋz./', 'lessons/are_you_a_workaholic/95_26_are_you_a_workaholic.mp3', 7.210, 14),
    (27, 'Reorganize your daily activities.', 'Sắp xếp lại hoạt động trong ngày.', '/riˈɔrgəˌnaɪz jʊr ˈdeɪli ækˈtɪvɪtiz./', 'lessons/are_you_a_workaholic/95_27_are_you_a_workaholic.mp3', 2.821, 4),
    (28, 'Working smart means you must maximize the time when you can work most effectively.', 'Làm việc thông minh đồng nghĩa với việc bạn phải tận dụng tối đa khoảng thời gian bạn có thể làm việc hiệu quả nhất.', '/ˈwərkɪŋ smɑrt minz ju məst ˈmæksəˌmaɪz ðə taɪm wɪn ju kən wərk moʊst ˈifɛktɪvli./', 'lessons/are_you_a_workaholic/95_28_are_you_a_workaholic.mp3', 5.224, 14),
    (29, 'Mark this time on your schedule for the most creative and important tasks you need to do.', 'Hãy đánh dấu trên thời gian biểu của mình để dành khoảng thời gian đó cho những việc sáng tạo và quan trọng nhất bạn cần làm.', '/mɑrk ðɪs taɪm ɔn jʊr ˈskɛʤʊl fər ðə moʊst kriˈeɪtɪv ənd ˌɪmˈpɔrtənt tæsks ju nid tɪ du./', 'lessons/are_you_a_workaholic/95_29_are_you_a_workaholic.mp3', 6.113, 17),
    (30, 'Don’t get swept up in other people''s schedules or demands.', 'Đừng bị cuốn theo lịch trình hay nhu cầu của người khác.', '/doʊnt gɪt swɛpt əp ɪn ˈəðər ˈpipəlz ˈskɛʤʊlz ər dɪˈmændz./', 'lessons/are_you_a_workaholic/95_30_are_you_a_workaholic.mp3', 3.788, 10),
    (31, 'Working smart allows you and your mind to rest so that you can return to work with a refreshed and clearer mindset.', 'Làm việc thông minh tạo điều kiện cho bạn và trí não bạn nghỉ ngơi, để sau đó có thể quay lại công việc với một tâm trí tươi mới và minh mẫn hơn.', '/ˈwərkɪŋ smɑrt əˈlaʊz ju ənd jʊr maɪnd tɪ rɛst soʊ ðət ju kən rɪˈtərn tɪ wərk wɪθ ə riˈfrɛʃt ənd ˈklɪrər ˈmaɪndˌsɛt./', 'lessons/are_you_a_workaholic/95_31_are_you_a_workaholic.mp3', 8.072, 22),
    (32, 'As a result, you will handle everything more efficiently during your work hours.', 'Nhờ đó, trong khoảng thời gian làm việc bạn sẽ xử lý mọi vấn đề hiệu quả hơn.', '/ɛz ə rɪˈzəlt, ju wɪl ˈhændəl ˈɛvriˌθɪŋ mɔr ɪˈfɪʃəntli ˈdʊrɪŋ jʊr wərk aʊərz./', 'lessons/are_you_a_workaholic/95_32_are_you_a_workaholic.mp3', 5.642, 13),
    (33, 'You can plan a walk, write a journal, play sports, or have dinner with people after work.', 'Bạn có thể lên kế hoạch đi dạo, viết nhật ký, chơi thể thao hoặc ăn tối với mọi người sau giờ làm việc.', '/ju kən plæn ə wɔk, raɪt ə ˈʤərnəl, pleɪ spɔrts, ər hæv ˈdɪnər wɪθ ˈpipəl ˈæftər wərk./', 'lessons/are_you_a_workaholic/95_33_are_you_a_workaholic.mp3', 6.139, 17),
    (34, 'Creating a new routine will help you forget your obsession with working at the office.', 'Việc tạo ra một thói quen mới sẽ giúp bạn quên đi sự ám ảnh của công việc ở cơ quan.', '/kriˈeɪtɪŋ ə nu ruˈtin wɪl hɛlp ju fərˈgɛt jʊr əbˈsɛʃən wɪθ ˈwərkɪŋ æt ðə ˈɔfəs./', 'lessons/are_you_a_workaholic/95_34_are_you_a_workaholic.mp3', 4.833, 15),
    (35, 'The important thing is to find a hobby that suits you.', 'Điều quan trọng là bạn cần tìm thấy sở thích phù hợp với bản thân.', '/ðə ˌɪmˈpɔrtənt θɪŋ ɪz tɪ faɪnd ə ˈhɑbi ðət suts ju./', 'lessons/are_you_a_workaholic/95_35_are_you_a_workaholic.mp3', 4.336, 11),
    (36, 'When you engage in these activities, you will be distracted and no longer think about work.', 'Khi tham gia những hoạt động đó, bạn sẽ bị phân tâm, không còn nhớ tới công việc nữa.', '/wɪn ju ɪnˈgeɪʤ ɪn ðiz ækˈtɪvɪtiz, ju wɪl bi dɪˈstræktɪd ənd noʊ ˈlɔŋgər θɪŋk əˈbaʊt wərk./', 'lessons/are_you_a_workaholic/95_36_are_you_a_workaholic.mp3', 6.269, 16),
    (37, 'Sacrificing health and joy is not a smart way to pursue the long career path ahead.', 'Đánh đổi sức khỏe và niềm vui không phải là cách thông minh để theo đuổi con đường sự nghiệp còn dài phía trước.', '/ˈsækrəˌfaɪsɪŋ hɛlθ ənd ʤɔɪ ɪz nɑt ə smɑrt weɪ tɪ pərˈsu ðə lɔŋ kərɪr pæθ əˈhɛd./', 'lessons/are_you_a_workaholic/95_37_are_you_a_workaholic.mp3', 5.747, 16),
    (38, 'Successful people know their time is valuable, but they do not spend it all on work; they also participate in outside activities.', 'Những người thành công biết rằng thời gian của họ là quý giá nhưng họ không hoàn toàn dành cho công việc mà còn tham gia những hoạt động bên ngoài.', '/səkˈsɛsfəl ˈpipəl noʊ ðɛr taɪm ɪz ˈvæljəbəl, bət ðeɪ du nɑt spɛnd ɪt ɔl ɔn wərk; ðeɪ ˈɔlsoʊ pɑrˈtɪsəˌpeɪt ɪn ˈaʊtˈsaɪd ækˈtɪvɪtiz./', 'lessons/are_you_a_workaholic/95_38_are_you_a_workaholic.mp3', 9.927, 22),
    (39, 'A balance between work and life will help each person be happier and more energized, leading to higher efficiency at work.', 'Sự cân bằng giữa công việc và cuộc sống sẽ giúp mỗi người hạnh phúc hơn, tràn đầy năng lượng để đạt được hiệu quả cao hơn trong công việc.', '/ə ˈbæləns bɪtˈwin wərk ənd laɪf wɪl hɛlp iʧ ˈpərsən bi ˈhæpiər ənd mɔr ˈɛnərˌʤaɪzd, ˈlidɪŋ tɪ haɪər ɪˈfɪʃənsi æt wərk./', 'lessons/are_you_a_workaholic/95_39_are_you_a_workaholic.mp3', 7.758, 21)
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



commit;

select
  l.slug,
  l.title,
  l.cefr,
  l.is_published,
  count(s.id) as segment_count
from public.listening_lessons l
left join public.listening_segments s on s.lesson_id = l.id
where l.slug = 'are_you_a_workaholic'
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
  where slug = 'are_you_a_workaholic'
)
order by order_index;
