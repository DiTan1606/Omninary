import Foundation
import Supabase

// Shared Supabase client used across the app
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://ihufnprjqpbllgifvter.supabase.co")!,
    supabaseKey: "sb_publishable_s_KT7O0uP6YMs9uUHILNAQ_vm9_cOiF"
)
