import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var installer = PatchInstaller()
    @State private var showFolderPicker = false

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.045).ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Text("SEKTXNTOBB")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white)

                Text("INJECTOR")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(Color.red)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: 58, height: 3)
                    .padding(.top, 8)

                Text(installer.status)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(installer.isSuccess ? .green : .white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 54)

                if installer.isWorking {
                    ProgressView()
                        .tint(.red)
                        .scaleEffect(1.2)
                }

                Button {
                    installer.inject()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                        Text("INJECT PATCH")
                            .tracking(1.5)
                    }
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(installer.isWorking || !installer.hasFolder)
                .opacity(installer.hasFolder ? 1 : 0.45)

                Button {
                    showFolderPicker = true
                } label: {
                    Text(installer.hasFolder ? "Paks folder linked" : "CHOOSE PAKS FOLDER")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.vertical, 12)
                }

                Spacer()

                Text("PATCH  •  game_patch_4.7.0.21760.pak")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 28)
        }
        .onAppear { installer.restoreFolderAccess() }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { installer.linkFolder(url) }
            case .failure(let error):
                installer.status = "Folder selection failed: \\(error.localizedDescription)"
            }
        }
    }
}

@MainActor
final class PatchInstaller: ObservableObject {
    @Published var status = "Link PUBG MOBILE Paks folder to continue"
    @Published var isWorking = false
    @Published var isSuccess = false
    @Published var hasFolder = false

    private let bookmarkKey = "paksFolderBookmark"
    private var folderURL: URL?

    func linkFolder(_ url: URL) {
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folderURL = url
            hasFolder = true
            status = "Paks folder linked. Ready to inject."
            isSuccess = false
        } catch {
            status = "Could not save folder permission: \\(error.localizedDescription)"
        }
    }

    func restoreFolderAccess() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                status = "Folder permission expired. Link the Paks folder again."
                hasFolder = false
                return
            }
            folderURL = url
            hasFolder = true
            status = "Paks folder linked. Ready to inject."
        } catch {
            status = "Folder permission unavailable. Link the Paks folder again."
            hasFolder = false
        }
    }

    func inject() {
        guard !isWorking, let folderURL else { return }
        isWorking = true
        isSuccess = false
        status = "Installing patch…"

        Task.detached { [weak self] in
            guard let self else { return }
            let source = Bundle.main.url(forResource: "game_patch_4.7.0.21760", withExtension: "pak")
            do {
                guard let source else { throw InstallerError.patchMissing }
                let access = folderURL.startAccessingSecurityScopedResource()
                defer { if access { folderURL.stopAccessingSecurityScopedResource() } }

                let destination = folderURL.appendingPathComponent("game_patch_4.7.0.21760.pak")
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var operationError: Error?

                coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinatedURL in
                    do {
                        let patchData = try Data(contentsOf: source)
                        try patchData.write(to: coordinatedURL, options: .atomic)
                        let writtenData = try Data(contentsOf: coordinatedURL)
                        guard writtenData.count == patchData.count else {
                            throw InstallerError.verificationFailed
                        }
                    } catch {
                        operationError = error
                    }
                }

                if let coordinationError { throw coordinationError }
                if let operationError { throw operationError }

                await MainActor.run {
                    self.isWorking = false
                    self.isSuccess = true
                    self.status = "PATCH INSTALLED\nsektxntobb готов к работе"
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    self.isSuccess = false
                    self.status = "Install failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

enum InstallerError: LocalizedError {
    case patchMissing
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .patchMissing: return "Embedded patch file is missing from the app."
        case .verificationFailed: return "The file was written but verification failed."
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }

    static func present(onPick: @escaping (URL?) -> Void) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            onPick(nil); return
        }
        let host = UIHostingController(rootView: FolderPicker(onPick: onPick))
        host.view.isHidden = true
        root.present(host, animated: false)
    }
}
