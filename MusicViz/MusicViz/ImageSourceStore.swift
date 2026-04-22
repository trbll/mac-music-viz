import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ImageSourceStore: ObservableObject {
    @Published private(set) var imageURL: URL?
    @Published private(set) var imageName: String?
    @Published private(set) var thumbnail: NSImage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var revision = 0

    private(set) var cgImage: CGImage?

    var hasImage: Bool { cgImage != nil }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    func load(url: URL) {
        guard Self.isSupportedImageURL(url) else {
            errorMessage = "Unsupported image file."
            return
        }
        guard let image = NSImage(contentsOf: url),
              let cgImage = Self.cgImage(from: image) else {
            errorMessage = "Could not load image."
            return
        }

        self.imageURL = url
        self.imageName = url.lastPathComponent
        self.thumbnail = image
        self.cgImage = cgImage
        self.errorMessage = nil
        revision &+= 1
    }

    func clear() {
        imageURL = nil
        imageName = nil
        thumbnail = nil
        cgImage = nil
        errorMessage = nil
        revision &+= 1
    }

    static func isSupportedImageURL(_ url: URL) -> Bool {
        guard url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
