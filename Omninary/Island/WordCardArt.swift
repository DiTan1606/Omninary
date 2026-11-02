import SwiftUI
import UIKit

// The word's own pixel picture from Storage (word-art bucket).

enum WordCardLinks {
    static let storageBase = "https://ihufnprjqpbllgifvter.supabase.co/storage/v1/object/public/word-art/"

    static func artURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: storageBase + path)
    }
}

@MainActor
final class WordArtStore: ObservableObject {
    static let shared = WordArtStore()
    @Published private(set) var images: [String: CGImage] = [:]
    private var loading: Set<String> = []
    private var failed: Set<String> = []

    func image(for path: String?) -> CGImage? {
        guard let path else { return nil }
        if let image = images[path] { return image }
        load(path)
        return nil
    }

    private func load(_ path: String) {
        guard !loading.contains(path), !failed.contains(path), let url = WordCardLinks.artURL(path) else { return }
        loading.insert(path)
        Task {
            defer { loading.remove(path) }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let image = UIImage(data: data)?.cgImage {
                images[path] = image
            } else {
                failed.insert(path)
            }
        }
    }
}

/// The word's picture; until it arrives (or if it is missing) the demo icon matched by meaning.
struct WordPictureView: View {
    let vocab: Vocabulary
    var size: CGFloat
    @ObservedObject private var store = WordArtStore.shared

    var body: some View {
        if let image = store.image(for: vocab.art_path) {
            Image(decorative: image, scale: 1).resizable().interpolation(.none).frame(width: size, height: size)
        } else {
            PixelArtView(key: WordArt.key(meaning: vocab.V_meaning, extra: vocab.EV_meaning), size: size * 0.8)
                .frame(width: size, height: size)
        }
    }
}
