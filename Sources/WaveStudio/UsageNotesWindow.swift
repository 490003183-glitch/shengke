import AppKit
import SwiftUI
import AudioCore

final class UsageNotesWindow:NSObject,NSTextViewDelegate {
    let view=NSView()
    var onPresent:(()->Void)?
    var onClose:(()->Void)?
    let store:UsageNotesStore
    private let textView:NotesTextView
    private let storage:NSTextStorage
    private let status=NSTextField(labelWithString:"")
    init(store:UsageNotesStore) {
        self.store=store
        let storage=NSTextStorage(),layout=NSLayoutManager(),container=NSTextContainer(size:NSSize(width:578,height:CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout);layout.addTextContainer(container)
        self.storage=storage
        textView=NotesTextView(frame:NSRect(x:0,y:0,width:578,height:350),textContainer:container)
        super.init()
        let root=view
        root.wantsLayer=true;root.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        let title=NSTextField(labelWithString:"使用建议 · v\(store.version)");title.font = .systemFont(ofSize:17,weight:.semibold)
        let subtitle=NSTextField(labelWithString:"随时记录，关闭即保存；升级版本也会保留。可拖入 .md 追加建议。")
        subtitle.font = .systemFont(ofSize:12);subtitle.textColor = .secondaryLabelColor
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        textView.minSize=NSSize(width:0,height:350);textView.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize=NSSize(width:578,height:CGFloat.greatestFiniteMagnitude)
        textView.isEditable=true;textView.isSelectable=true
        textView.isRichText=false;textView.isAutomaticQuoteSubstitutionEnabled=false;textView.isAutomaticDashSubstitutionEnabled=false
        textView.allowsUndo=true;textView.font = .systemFont(ofSize:14);textView.textContainerInset=NSSize(width:12,height:12)
        textView.isVerticallyResizable=true;textView.isHorizontallyResizable=false;textView.autoresizingMask=[.width]
        textView.textContainer?.widthTracksTextView=true;textView.string=store.text;textView.delegate=self
        textView.setAccessibilityLabel("使用建议正文")
        textView.importFile={ [weak self] url in self?.importFile(url) }
        scroll.documentView=textView
        status.font = .systemFont(ofSize:11);status.textColor = .secondaryLabelColor;status.stringValue="已保存 · v\(store.version)"
        let done=NSButton(title:"关闭",target:self,action:#selector(closeNotes));done.bezelStyle = .rounded
        for v in [title,subtitle,scroll,status,done] {v.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(v)}
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),title.topAnchor.constraint(equalTo:root.topAnchor,constant:14),
            subtitle.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),subtitle.topAnchor.constraint(equalTo:title.bottomAnchor,constant:8),subtitle.trailingAnchor.constraint(lessThanOrEqualTo:root.trailingAnchor,constant:-16),
            scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-16),scroll.topAnchor.constraint(equalTo:subtitle.bottomAnchor,constant:12),scroll.bottomAnchor.constraint(equalTo:done.topAnchor,constant:-12),
            done.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-16),done.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-12),
            status.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),status.centerYAnchor.constraint(equalTo:done.centerYAnchor)
        ])
    }
    func present() {
        onPresent?()
        DispatchQueue.main.async {self.textView.window?.makeFirstResponder(self.textView)}
    }
    func textDidChange(_ notification:Notification) {_=save()}
    @discardableResult func save()->Bool {
        do {try store.save(textView.string);status.stringValue="已保存 · v\(store.version)";return true}
        catch {status.stringValue="未能保存：\(error.localizedDescription)";return false}
    }
    @objc private func closeNotes() {if save() {onClose?()}}
    func importFile(_ url:URL) {
        do {
            guard save() else{return}
            textView.string=try store.importMarkdown(url);status.stringValue="已追加并保存 · \(url.lastPathComponent)";present()
        } catch {let alert=NSAlert(error:error);if let window=view.window {alert.beginSheetModal(for:window)} }
    }
}
private final class NotesTextView:NSTextView {
    var importFile:((URL)->Void)?
    override init(frame:NSRect,textContainer:NSTextContainer?) {super.init(frame:frame,textContainer:textContainer);registerForDraggedTypes([.fileURL])}
    required init?(coder:NSCoder) {fatalError()}
    private func file(_ sender:NSDraggingInfo)->URL? {(sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL])?.first}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {
        if let url=file(sender) {return ["md","markdown"].contains(url.pathExtension.lowercased()) ? .copy : []}
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        if let url=file(sender),["md","markdown"].contains(url.pathExtension.lowercased()) {importFile?(url);return true}
        return super.performDragOperation(sender)
    }
}

struct UsageNotesSurface:NSViewRepresentable {
    let view:NSView
    func makeNSView(context:Context)->NSView {view}
    func updateNSView(_ nsView:NSView,context:Context) {}
}
