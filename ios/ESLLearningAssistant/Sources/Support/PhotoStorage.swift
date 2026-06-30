import UIKit

enum PhotoStorage {
    private static var directoryURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            return fileName
        } catch {
            return nil
        }
    }

    static func loadImage(fileName: String) -> UIImage? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: fileURL.path)
    }
}
