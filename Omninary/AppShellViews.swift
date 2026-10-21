import SwiftUI

struct HomePlaceholderView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    private var interfaceMode: AppInterfaceMode {
        AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    NavigationLink(destination: NotificationView()) {
                        Image(interfaceMode.wordmarkAsset)
                            .resizable()
                            .scaledToFit()
                            .frame(height: interfaceMode.usesDarkTheme ? 24 : 38)
                            .accessibilityLabel(interfaceMode.title)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Spacer()
            }
            .background((interfaceMode.usesDarkTheme ? Color.black : Color.white).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct BlankTabView: View {
    let title: String
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    private var interfaceMode: AppInterfaceMode {
        AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 40)
                    Image(systemName: title == "Library" ? "books.vertical" : "graduationcap")
                        .font(.system(size: 64))
                        .foregroundStyle(interfaceMode.usesDarkTheme ? ExtraAuroraPalette.ice.opacity(0.4) : Color.blue.opacity(0.4))
                    Text("Nội dung cho mục \(title) đang được hoàn thiện.")
                        .font(.subheadline)
                        .foregroundStyle(interfaceMode.usesDarkTheme ? Color.white.opacity(0.6) : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .background {
                if interfaceMode.usesDarkTheme {
                    AuroraBackdrop()
                } else {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                }
            }
        }
    }
}
