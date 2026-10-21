"""Rebuild the Supabase delivery file from the canonical workflow sources."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
economy = (root / 'omni_points_and_icons.sql').read_text()
profile_columns = economy[economy.index('ALTER TABLE public.profiles'):economy.index('ALTER TABLE public.user_stats')]
auth_helper = re.search(r'CREATE OR REPLACE FUNCTION public.require_current_user\(\).*?\n\$\$;', economy, re.S).group(0)
header = '''-- GIỮ CHUỖI, VẬT PHẨM VÀ GHI NHẬN PHIÊN HỌC THỐNG NHẤT
-- Chạy nguyên tệp trong trình SQL của Supabase. Có thể chạy lại.
-- Yêu cầu các bảng nền hiện có: profiles, user_stats, activity_logs, user_vocabulary.
-- Không xóa tài khoản, điểm, chuỗi hoặc lịch sử học. Ghi đè các hàm liên quan.
-- Không thay đổi các hàm trang bị biểu tượng hoặc các tính năng khác của ứng dụng.
BEGIN;
'''
security = economy[economy.index('-- Remove the broad prototype policy.'):economy.index('CREATE OR REPLACE FUNCTION public.require_current_user()')]
foundation = profile_columns + '\n' + security + '\n' + auth_helper + '''
REVOKE ALL ON FUNCTION public.require_current_user() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_current_user() TO authenticated;
CREATE UNIQUE INDEX IF NOT EXISTS activity_logs_user_date_unique ON public.activity_logs(user_id, date);
REVOKE INSERT, UPDATE, DELETE ON public.user_stats, public.activity_logs FROM authenticated;
'''
parts = ['omni_item_catalog.sql', 'streak_workflow.sql', 'ditandnary_review_schedule_v2.sql', 'vocabulary_learning_atomic_flow.sql', 'extra_v1_learning_telemetry.sql']
def source(name):
    body = (root/name).read_text()
    if name == 'ditandnary_review_schedule_v2.sql':
        body = body.replace('BEGIN;\n', '', 1).removesuffix('\nCOMMIT;\n')
    return '-- SOURCE: '+name+'\n'+body
result = header + '\n' + foundation + '\n\n' + '\n\n'.join(source(name) for name in parts) + '\nCOMMIT;\n'
(root / 'omninary_unified.sql').write_text(result)

# Small deployment for an existing project that already has the learning and
# reward infrastructure. Keep migration and function replacement atomic.
learning = (root / 'vocabulary_learning_atomic_flow.sql').read_text()
def between(start, end):
    return learning[learning.index(start):learning.index(end)].rstrip()
migration = (root / 'ditandnary_review_schedule_v2.sql').read_text()
migration = migration[migration.index('CREATE TABLE IF NOT EXISTS public.ditandnary_schedule_migrations'):migration.rindex('COMMIT;')].rstrip()
focused = '\n\n'.join([
    '-- DITANDNARY REVIEW SCHEDULE V2',
    '-- Run this whole file once in the Supabase SQL Editor on the existing project.',
    '-- It migrates legacy levels and replaces only the progress-related functions.',
    '-- Safe to rerun: the level conversion is guarded by a migration record.',
    'BEGIN;',
    migration,
    between('CREATE OR REPLACE FUNCTION public.protect_new_user_vocabulary_progress()', 'CREATE OR REPLACE FUNCTION public.get_learning_access_state()'),
    between('CREATE OR REPLACE FUNCTION public.start_vocabulary_learning(', 'CREATE OR REPLACE FUNCTION public.complete_vocabulary_learning_session('),
    between('CREATE OR REPLACE FUNCTION public.complete_vocabulary_learning_session(', 'REVOKE ALL ON FUNCTION public.get_learning_access_state()'),
    'REVOKE ALL ON FUNCTION public.start_vocabulary_learning(text[]) FROM PUBLIC;\n'
    'REVOKE ALL ON FUNCTION public.complete_vocabulary_learning_session(uuid, text[], integer) FROM PUBLIC;\n'
    'GRANT EXECUTE ON FUNCTION public.start_vocabulary_learning(text[]) TO authenticated;\n'
    'GRANT EXECUTE ON FUNCTION public.complete_vocabulary_learning_session(uuid, text[], integer) TO authenticated;',
    'COMMIT;'
]) + '\n'
(root / 'ditandnary_review_schedule_deploy.sql').write_text(focused)
