import Foundation

public final class UsageNotesStore {
    public let url:URL
    public let version:String
    public private(set) var text:String
    public init(url:URL,version:String) throws {
        self.url=url;self.version=version
        if FileManager.default.fileExists(atPath:url.path) {text=Self.body(try String(contentsOf:url,encoding:.utf8))}
        else {text=""}
        // One stable file; upgrading only refreshes the version, retaining every note.
        try save(text)
    }
    public func save(_ text:String) throws {
        let contents="<!-- WaveStudio usage-notes -->\n# 声刻使用建议\n\n当前版本：\(version)\n\n<!-- notes -->\n"+text
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try contents.write(to:url,atomically:true,encoding:.utf8)
        self.text=text
    }
    public func importMarkdown(_ file:URL) throws -> String {
        guard ["md","markdown"].contains(file.pathExtension.lowercased()) else {throw AudioError.invalid("请拖入 Markdown（.md）建议文件。")}
        let bytes=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard bytes<=2_000_000 else {throw AudioError.invalid("建议文件超过 2 MB，未导入。")}
        let imported=Self.body(try String(contentsOf:file,encoding:.utf8))
        // Import appends so existing advice cannot disappear on an accidental drop.
        let combined=text.isEmpty ? imported : text+"\n\n"+imported
        try save(combined);return combined
    }
    private static func body(_ raw:String)->String {
        guard raw.hasPrefix("<!-- WaveStudio usage-notes -->"),let marker=raw.range(of:"<!-- notes -->\n") else {return raw}
        return String(raw[marker.upperBound...])
    }
}
