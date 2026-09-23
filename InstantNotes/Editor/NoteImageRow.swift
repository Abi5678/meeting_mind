//
//  NoteImageRow.swift
//  Instant Notes
//
// A photo block on the page, and the ways a photo gets into a note: the camera, the photo
// library, or a file.

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Row

/// A photo sized to the column and rounded up to whole ruling lines, so the paper's lines
/// still meet above and below it. Tap selects it, which is how Delete and Move reach it.
struct NoteImageRow: View {
    let imageID: UUID
    let pitch: CGFloat
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var image: UIImage?
    @State private var width: CGFloat = 0

    private var inset: CGFloat { (pitch / 4).rounded() }

    /// The photo fitted to the column, no taller than about half a phone screen.
    private var displaySize: CGSize {
        guard let image, width > 0, image.size.width > 0 else { return CGSize(width: width, height: pitch * 4) }
        let scale = min(width / image.size.width, (pitch * 14) / image.size.height, 1.5)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private var rowHeight: CGFloat {
        ((displaySize.height + inset * 2) / pitch).rounded(.up) * pitch
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color("InkColor").opacity(0.06))
                    .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.secondary) }
                    .frame(height: displaySize.height)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .padding(.top, inset)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .task(id: imageID) { image = NoteImageCache.image(for: imageID, in: modelContext) }
        .accessibilityElement()
        .accessibilityLabel("Photo")
        .accessibilityAddTraits(.isImage)
    }
}

/// Decoded photos, so scrolling past a photo doesn't decode its JPEG again.
@MainActor
enum NoteImageCache {
    private static let cache = NSCache<NSUUID, UIImage>()

    static func image(for id: UUID, in context: ModelContext) -> UIImage? {
        if let cached = cache.object(forKey: id as NSUUID) { return cached }
        var descriptor = FetchDescriptor<NoteImage>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let stored = try? context.fetch(descriptor).first,
              let full = UIImage(data: stored.data) else { return nil }
        // Big enough for a page on any screen; a quarter of the memory of the full photo.
        let image = full.preparingThumbnail(of: fitting(full.size, within: 1200)) ?? full
        cache.setObject(image, forKey: id as NSUUID)
        return image
    }

    private static func fitting(_ size: CGSize, within side: CGFloat) -> CGSize {
        let scale = min(1, side / max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

// MARK: - Input

enum PhotoSource: Identifiable {
    case camera, library, files
    var id: Self { self }

    static var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
}

/// Presents the camera, the photo library or a file picker for `source`, and hands back the
/// photos picked, in the order picked.
struct PhotoInput: ViewModifier {
    @Binding var source: PhotoSource?
    let onPick: ([UIImage]) -> Void

    @State private var libraryItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: showing(.library), selection: $libraryItems, maxSelectionCount: 10, matching: .images)
            .onChange(of: libraryItems) { _, items in
                guard !items.isEmpty else { return }
                libraryItems = []
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    if !images.isEmpty { onPick(images) }
                }
            }
            .fileImporter(isPresented: showing(.files), allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result else { return }
                let images = urls.compactMap { url -> UIImage? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
                }
                if !images.isEmpty { onPick(images) }
            }
            .fullScreenCover(isPresented: showing(.camera)) {
                CameraPicker { image in
                    source = nil
                    if let image { onPick([image]) }
                }
                .ignoresSafeArea()
            }
    }

    private func showing(_ kind: PhotoSource) -> Binding<Bool> {
        Binding(get: { source == kind }, set: { if !$0, source == kind { source = nil } })
    }
}

/// The system camera. SwiftUI has no camera view of its own.
private struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
