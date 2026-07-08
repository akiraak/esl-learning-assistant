import Foundation
import Testing
@testable import ESLLearningAssistant

/// `DocumentStorage`（原本の保存/参照/削除）と `DocumentKind`（拡張子↔種別↔mediaType）を検証する。
/// 保存はアプリサンドボックスの Documents/Documents に実ファイルを書くため、各テストは
/// `save` が返す一意の `UUID.ext` 名だけを掃除する（`deleteAll` はディレクトリごと消し
/// 並列実行中の他テストと競合しうるため使わない）。
struct DocumentStorageTests {
    private func sampleData(_ marker: String = "pdf-bytes") -> Data {
        Data(marker.utf8)
    }

    @Test func saveWritesFileAndReturnsUUIDName() throws {
        let data = sampleData("hello-document")
        let fileName = try #require(DocumentStorage.save(data: data, ext: "pdf"))
        defer { DocumentStorage.delete(fileName: fileName) }

        #expect(fileName.hasSuffix(".pdf"))
        #expect(UUID(uuidString: (fileName as NSString).deletingPathExtension) != nil)
        #expect(DocumentStorage.exists(fileName: fileName))
        let roundTrip = try Data(contentsOf: DocumentStorage.url(fileName: fileName))
        #expect(roundTrip == data)
    }

    @Test func saveLowercasesExtension() throws {
        let fileName = try #require(DocumentStorage.save(data: sampleData(), ext: "DOCX"))
        defer { DocumentStorage.delete(fileName: fileName) }
        #expect(fileName.hasSuffix(".docx"))
    }

    @Test func saveWithEmptyExtensionReturnsBareUUID() throws {
        let fileName = try #require(DocumentStorage.save(data: sampleData(), ext: ""))
        defer { DocumentStorage.delete(fileName: fileName) }
        #expect(!fileName.contains("."))
        #expect(UUID(uuidString: fileName) != nil)
        #expect(DocumentStorage.exists(fileName: fileName))
    }

    @Test func deleteRemovesFile() throws {
        let fileName = try #require(DocumentStorage.save(data: sampleData(), ext: "pdf"))
        #expect(DocumentStorage.exists(fileName: fileName))
        DocumentStorage.delete(fileName: fileName)
        #expect(!DocumentStorage.exists(fileName: fileName))
    }

    @Test func existsIsFalseForUnknownFile() {
        #expect(!DocumentStorage.exists(fileName: "\(UUID().uuidString).pdf"))
    }
}

/// `DocumentKind` の拡張子・mediaType 対応。mediaType は backend の
/// `SUPPORTED_DOCUMENT_MIME_EXTENSIONS`（documentExtract.ts）と一致していること。
struct DocumentKindTests {
    @Test func initFromFileExtensionIsCaseInsensitive() {
        #expect(DocumentKind(fileExtension: "pdf") == .pdf)
        #expect(DocumentKind(fileExtension: "PDF") == .pdf)
        #expect(DocumentKind(fileExtension: "docx") == .docx)
        #expect(DocumentKind(fileExtension: "DOCX") == .docx)
    }

    @Test func initFromUnsupportedExtensionIsNil() {
        #expect(DocumentKind(fileExtension: "doc") == nil) // レガシー .doc は非対象
        #expect(DocumentKind(fileExtension: "txt") == nil)
        #expect(DocumentKind(fileExtension: "") == nil)
    }

    @Test func fileExtensionRoundTrips() {
        #expect(DocumentKind.pdf.fileExtension == "pdf")
        #expect(DocumentKind.docx.fileExtension == "docx")
        #expect(DocumentKind(fileExtension: DocumentKind.pdf.fileExtension) == .pdf)
        #expect(DocumentKind(fileExtension: DocumentKind.docx.fileExtension) == .docx)
    }

    @Test func mediaTypeMatchesBackendWhitelist() {
        #expect(DocumentKind.pdf.mediaType == "application/pdf")
        #expect(DocumentKind.docx.mediaType
            == "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    }
}
