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
                    Image(interfaceMode.wordmarkAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 42)
                        .accessibilityLabel(interfaceMode.title)

                    Spacer()

                    NavigationLink(destination: NotificationView()) {
                        Image(systemName: "bell.fill")
                            .font(.title3)
                            .foregroundStyle(interfaceMode.usesDarkTheme ? Color.white : Color.primary)
                            .padding(12)
                            .background(Circle().fill(interfaceMode.usesDarkTheme ? Color.white.opacity(0.12) : Color.black.opacity(0.05)))
                    }
                    .accessibilityLabel("Thông báo")
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
            Color(interfaceMode.usesDarkTheme ? .black : .white)
                .ignoresSafeArea()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
        }
    }
}
