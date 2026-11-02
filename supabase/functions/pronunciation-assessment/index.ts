import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const maxAudioBytes = 2 * 1024 * 1024;

type VocabularyCatalog = {
  word: string | null;
  e_example: string | null;
};

type UserVocabularyLink = {
  user_id: string;
  vocab_catalog: VocabularyCatalog | VocabularyCatalog[] | null;
};

type ListeningSegmentReference = {
  id: string;
  lesson_id: string;
  english_text: string | null;
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function base64Utf8(value: string) {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function score(value: unknown) {
  const number = typeof value === "number" ? value : 0;
  return Math.round(number * 10) / 10;
}

function milliseconds(value: unknown) {
  const ticks = typeof value === "number" && Number.isFinite(value) ? value : null;
  return ticks === null || ticks < 0 ? null : Math.round(ticks / 10_000);
}

function assessmentFields(value: Record<string, unknown>) {
  const nested = value.PronunciationAssessment;
  return nested && typeof nested === "object"
    ? nested as Record<string, unknown>
    : value;
}

function namedSupabaseKey(environmentVariable: string) {
  const rawValue = Deno.env.get(environmentVariable)?.trim();
  if (!rawValue) return undefined;

  try {
    const keys = JSON.parse(rawValue);
    if (!keys || typeof keys !== "object" || Array.isArray(keys)) {
      return undefined;
    }

    const values = keys as Record<string, unknown>;
    const defaultKey = values.default;
    if (typeof defaultKey === "string" && defaultKey.trim()) {
      return defaultKey.trim();
    }

    const firstKey = Object.values(values).find((value): value is string => (
      typeof value === "string" && value.trim().length > 0
    ));
    return firstKey?.trim();
  } catch {
    return undefined;
  }
}

function firstConfiguredValue(...environmentVariables: string[]) {
  for (const environmentVariable of environmentVariables) {
    const value = Deno.env.get(environmentVariable)?.trim();
    if (value) return value;
  }

  return undefined;
}

function supabasePublishableKey() {
  return namedSupabaseKey("SUPABASE_PUBLISHABLE_KEYS")
    ?? firstConfiguredValue("SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY");
}

function supabaseSecretKey() {
  return namedSupabaseKey("SUPABASE_SECRET_KEYS")
    ?? firstConfiguredValue("SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY");
}

const criticalPronunciationErrorTypes = new Set([
  "mispronunciation",
  "omission",
  "insertion",
]);

function normalizedErrorType(value: unknown) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function usableExample(value: string | null | undefined) {
  const trimmed = value?.trim() ?? "";
  return trimmed === "..." || trimmed === "…" ? "" : trimmed;
}

function shadowingPasses(
  scores: { pronunciation: number; accuracy: number; fluency: number; completeness: number },
  words: Array<{ accuracy: number; errorType: string }>,
) {
  return scores.pronunciation >= 82
    && scores.accuracy >= 80
    && scores.fluency >= 65
    && scores.completeness >= 95
    && words.length > 0
    && !words.some((word) => criticalPronunciationErrorTypes.has(normalizedErrorType(word.errorType)))
    && !words.some((word) => word.accuracy < 70);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return jsonResponse({ error: "Bạn cần đăng nhập để kiểm tra phát âm." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseKey = supabasePublishableKey();
  const serviceRoleKey = supabaseSecretKey();
  const azureSpeechKey = Deno.env.get("AZURE_SPEECH_KEY");
  const azureSpeechRegion = Deno.env.get("AZURE_SPEECH_REGION");

  if (!supabaseUrl || !supabaseKey || !serviceRoleKey || !azureSpeechKey || !azureSpeechRegion) {
    const missingConfiguration = [
      !supabaseUrl ? "SUPABASE_URL" : null,
      !supabaseKey ? "Supabase publishable/anon key" : null,
      !serviceRoleKey ? "Supabase secret/service-role key" : null,
      !azureSpeechKey ? "AZURE_SPEECH_KEY" : null,
      !azureSpeechRegion ? "AZURE_SPEECH_REGION" : null,
    ].filter(Boolean);
    console.error("Missing required Edge Function configuration.", { missingConfiguration });
    return jsonResponse({ error: "Dịch vụ kiểm tra phát âm chưa được cấu hình." }, 500);
  }

  const authClient = createClient(supabaseUrl, supabaseKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: userError } = await authClient.auth.getUser();

  if (userError || !user) {
    return jsonResponse({ error: "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại." }, 401);
  }

  let formData: FormData;
  try {
    formData = await request.formData();
  } catch {
    return jsonResponse({ error: "Dữ liệu ghi âm không hợp lệ." }, 400);
  }

  const userVocabularyId = formData.get("userVocabularyId");
  const listeningSegmentId = formData.get("listeningSegmentId");
  const audio = formData.get("audio");
  const hasVocabularyTarget = typeof userVocabularyId === "string" && userVocabularyId.length > 0;
  const hasListeningTarget = typeof listeningSegmentId === "string" && listeningSegmentId.length > 0;
  if (!(audio instanceof File) || hasVocabularyTarget === hasListeningTarget) {
    return jsonResponse({ error: "Thiếu dữ liệu bài phát âm." }, 400);
  }

  if (audio.size === 0 || audio.size > maxAudioBytes) {
    return jsonResponse({ error: "File ghi âm cần ngắn hơn 30 giây." }, 400);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  let referenceText = "";
  let listeningSegment: ListeningSegmentReference | null = null;

  if (hasVocabularyTarget) {
    const { data: userVocabulary, error: vocabularyError } = await adminClient
      .from("user_vocabulary")
      .select("user_id,vocab_catalog(word,e_example)")
      .eq("id", userVocabularyId)
      .eq("user_id", user.id)
      .single<UserVocabularyLink>();

    if (vocabularyError || !userVocabulary) {
      return jsonResponse({ error: "Không tìm thấy từ vựng cần kiểm tra." }, 404);
    }

    const catalog = Array.isArray(userVocabulary.vocab_catalog)
      ? userVocabulary.vocab_catalog[0]
      : userVocabulary.vocab_catalog;
    referenceText = usableExample(catalog?.e_example);

    if (!referenceText) {
      return jsonResponse({ error: "Từ này chưa có câu ví dụ để kiểm tra phát âm." }, 422);
    }
  } else {
    const { data: segment, error: segmentError } = await adminClient
      .from("listening_segments")
      .select("id,lesson_id,english_text")
      .eq("id", listeningSegmentId)
      .single<ListeningSegmentReference>();

    if (segmentError || !segment) {
      return jsonResponse({ error: "Không tìm thấy câu Shadowing cần kiểm tra." }, 404);
    }

    const { data: libraryEntry, error: libraryError } = await adminClient
      .from("user_listening_lessons")
      .select("user_id,lesson_id,is_in_shadowing,shadowing_best_score,shadowing_completed_at")
      .eq("user_id", user.id)
      .eq("lesson_id", segment.lesson_id)
      .maybeSingle();

    if (libraryError || !libraryEntry) {
      return jsonResponse({ error: "Bạn cần tải bài nghe này vào thư viện trước khi luyện Shadowing." }, 403);
    }

    if (!libraryEntry.is_in_shadowing && !libraryEntry.shadowing_completed_at) {
      return jsonResponse({ error: "Bạn cần đưa bài này vào luyện Shadowing trước." }, 403);
    }

    listeningSegment = segment;
    referenceText = segment.english_text?.trim() ?? "";
    if (!referenceText) {
      return jsonResponse({ error: "Câu Shadowing này chưa có nội dung tiếng Anh." }, 422);
    }
  }

  const assessmentParameters = base64Utf8(JSON.stringify({
    ReferenceText: referenceText,
    GradingSystem: "HundredMark",
    Granularity: "Phoneme",
    PhonemeAlphabet: "IPA",
    NBestPhonemeCount: 3,
    Dimension: "Comprehensive",
    EnableMiscue: "True",
  }));

  const endpoint = new URL(
    `https://${azureSpeechRegion}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1`,
  );
  endpoint.searchParams.set("language", "en-US");
  endpoint.searchParams.set("format", "detailed");
  endpoint.searchParams.set("profanity", "raw");

  let azureResponse: Response;
  try {
    azureResponse = await fetch(endpoint, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "audio/wav; codecs=audio/pcm; samplerate=16000",
        "Ocp-Apim-Subscription-Key": azureSpeechKey,
        "Pronunciation-Assessment": assessmentParameters,
      },
      body: await audio.arrayBuffer(),
    });
  } catch (error) {
    console.error("Azure Speech request failed.", error);
    return jsonResponse({ error: "Không thể kết nối dịch vụ kiểm tra phát âm. Vui lòng thử lại." }, 502);
  }

  const azureBody = await azureResponse.json().catch(() => null);
  if (!azureResponse.ok) {
    console.error("Azure Speech returned an error.", { status: azureResponse.status, azureBody });
    return jsonResponse({ error: "Không thể chấm điểm bản ghi âm này. Vui lòng thu âm lại." }, 422);
  }

  const bestResult = azureBody?.NBest?.[0];
  if (azureBody?.RecognitionStatus !== "Success" || !bestResult) {
    return jsonResponse({ error: "Chưa nghe rõ giọng đọc. Hãy thu âm lại ở nơi yên tĩnh hơn." }, 422);
  }

  const resultAssessment = assessmentFields(bestResult);
  const words = Array.isArray(bestResult.Words)
    ? bestResult.Words.map((word: Record<string, unknown>) => {
        const wordAssessment = assessmentFields(word);
        return {
          word: typeof word.Word === "string" ? word.Word : "",
          accuracy: score(wordAssessment.AccuracyScore),
          errorType: typeof wordAssessment.ErrorType === "string" ? wordAssessment.ErrorType : "None",
          offsetMilliseconds: milliseconds(word.Offset),
          durationMilliseconds: milliseconds(word.Duration),
          phonemes: Array.isArray(word.Phonemes)
            ? word.Phonemes.map((phoneme: Record<string, unknown>) => {
                const phonemeAssessment = assessmentFields(phoneme);
                const bestCandidate = Array.isArray(phonemeAssessment.NBestPhonemes)
                  ? phonemeAssessment.NBestPhonemes.find((candidate): candidate is Record<string, unknown> => (
                    candidate !== null && typeof candidate === "object"
                  ))
                  : undefined;
                return {
                  phoneme: typeof phoneme.Phoneme === "string" ? phoneme.Phoneme : "",
                  accuracy: score(phonemeAssessment.AccuracyScore),
                  heardPhoneme: typeof bestCandidate?.Phoneme === "string" ? bestCandidate.Phoneme : null,
                  heardScore: typeof bestCandidate?.Score === "number" ? score(bestCandidate.Score) : null,
                };
              })
            : [],
        };
      })
    : [];

  const scores = {
    pronunciation: score(resultAssessment.PronScore),
    accuracy: score(resultAssessment.AccuracyScore),
    fluency: score(resultAssessment.FluencyScore),
    completeness: score(resultAssessment.CompletenessScore),
  };

  let shadowingProgress: Record<string, unknown> | null = null;
  if (listeningSegment) {
    const now = new Date().toISOString();
    const { data: currentProgress, error: currentProgressError } = await adminClient
      .from("user_shadowing_progress")
      .select("attempts,best_score,status,passed_at")
      .eq("user_id", user.id)
      .eq("segment_id", listeningSegment.id)
      .maybeSingle();

    if (currentProgressError) {
      console.error("Unable to read shadowing progress.", currentProgressError);
      return jsonResponse({ error: "Không thể lưu tiến độ Shadowing. Vui lòng thử lại." }, 500);
    }

    const attemptPassed = shadowingPasses(scores, words);
    const wasPassed = currentProgress?.status === "passed";
    const nextBestScore = Math.max(
      typeof currentProgress?.best_score === "number" ? currentProgress.best_score : 0,
      scores.pronunciation,
    );

    const { error: saveProgressError } = await adminClient
      .from("user_shadowing_progress")
      .upsert({
        user_id: user.id,
        segment_id: listeningSegment.id,
        status: attemptPassed || wasPassed ? "passed" : "practicing",
        attempts: (typeof currentProgress?.attempts === "number" ? currentProgress.attempts : 0) + 1,
        latest_score: scores.pronunciation,
        best_score: nextBestScore,
        accuracy_score: scores.accuracy,
        fluency_score: scores.fluency,
        completeness_score: scores.completeness,
        passed_at: currentProgress?.passed_at ?? (attemptPassed ? now : null),
        updated_at: now,
      }, { onConflict: "user_id,segment_id" });

    if (saveProgressError) {
      console.error("Unable to write shadowing progress.", saveProgressError);
      return jsonResponse({ error: "Không thể lưu tiến độ Shadowing. Vui lòng thử lại." }, 500);
    }

    const { data: lessonSegments, error: lessonSegmentsError } = await adminClient
      .from("listening_segments")
      .select("id")
      .eq("lesson_id", listeningSegment.lesson_id);

    if (lessonSegmentsError || !lessonSegments?.length) {
      console.error("Unable to read shadowing lesson segments.", lessonSegmentsError);
      return jsonResponse({ error: "Không thể cập nhật tiến độ bài Shadowing." }, 500);
    }

    const segmentIds = lessonSegments.map((segment) => segment.id);
    const { data: lessonProgressRows, error: lessonProgressError } = await adminClient
      .from("user_shadowing_progress")
      .select("segment_id,status,latest_score,best_score")
      .eq("user_id", user.id)
      .in("segment_id", segmentIds);

    if (lessonProgressError) {
      console.error("Unable to calculate shadowing lesson progress.", lessonProgressError);
      return jsonResponse({ error: "Không thể cập nhật tiến độ bài Shadowing." }, 500);
    }

    const progressBySegmentId = new Map((lessonProgressRows ?? []).map((progress) => [progress.segment_id, progress]));
    const passedSegmentCount = segmentIds.filter((segmentId) => progressBySegmentId.get(segmentId)?.status === "passed").length;
    const lessonLatestScore = score(segmentIds.reduce((total, segmentId) => {
      const progress = progressBySegmentId.get(segmentId);
      return total + (typeof progress?.latest_score === "number" ? progress.latest_score : 0);
    }, 0) / segmentIds.length);
    const lessonBestScore = score(segmentIds.reduce((total, segmentId) => {
      const progress = progressBySegmentId.get(segmentId);
      return total + (typeof progress?.best_score === "number" ? progress.best_score : 0);
    }, 0) / segmentIds.length);
    const lessonPassed = passedSegmentCount === segmentIds.length;

    const { data: libraryEntry, error: libraryEntryError } = await adminClient
      .from("user_listening_lessons")
      .select("shadowing_best_score,shadowing_completed_at")
      .eq("user_id", user.id)
      .eq("lesson_id", listeningSegment.lesson_id)
      .single();

    if (libraryEntryError || !libraryEntry) {
      console.error("Unable to read shadowing library entry.", libraryEntryError);
      return jsonResponse({ error: "Không thể cập nhật tiến độ bài Shadowing." }, 500);
    }

    const { error: updateLessonError } = await adminClient
      .from("user_listening_lessons")
      .update({
        is_in_shadowing: !lessonPassed,
        shadowing_completed_at: lessonPassed ? (libraryEntry.shadowing_completed_at ?? now) : null,
        shadowing_latest_score: lessonLatestScore,
        shadowing_best_score: Math.max(
          typeof libraryEntry.shadowing_best_score === "number" ? libraryEntry.shadowing_best_score : 0,
          lessonBestScore,
        ),
      })
      .eq("user_id", user.id)
      .eq("lesson_id", listeningSegment.lesson_id);

    if (updateLessonError) {
      console.error("Unable to update shadowing lesson status.", updateLessonError);
      return jsonResponse({ error: "Không thể cập nhật tiến độ bài Shadowing." }, 500);
    }

    shadowingProgress = {
      status: attemptPassed || wasPassed ? "passed" : "practicing",
      attemptPassed,
      attempts: (typeof currentProgress?.attempts === "number" ? currentProgress.attempts : 0) + 1,
      latestScore: scores.pronunciation,
      bestScore: nextBestScore,
      passedSegmentCount,
      totalSegmentCount: segmentIds.length,
      lessonLatestScore,
      lessonBestScore,
      lessonPassed,
    };
  }

  return jsonResponse({
    referenceText,
    transcript: bestResult.Display ?? azureBody.DisplayText ?? "",
    scores,
    words,
    shadowingProgress,
  });
});
