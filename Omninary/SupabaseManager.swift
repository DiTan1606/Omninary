import Foundation
import Supabase

enum AppSupabaseConfiguration {
    static let url = URL(string: "https://ihufnprjqpbllgifvter.supabase.co")!
    // This is the existing client publishable key, never an administrative/service key.
    static let publishableKey = "sb_publishable_s_KT7O0uP6YMs9uUHILNAQ_vm9_cOiF"
}

// Shared Supabase client used across the app
let supabase = SupabaseClient(
    supabaseURL: AppSupabaseConfiguration.url,
    supabaseKey: AppSupabaseConfiguration.publishableKey,
    options: .init(
        auth: .init(emitLocalSessionAsInitialSession: true)
    )
)
