import AppKit
import AudioCore
import UniformTypeIdentifiers

/// The format picker lives in the native save sheet, preserving the three-button workflow.
final class SaveCopyAccessory:NSObject {
    let view=NSView(frame:NSRect(x:0,y:0,width:460,height:78))
    let popup=NSPopUpButton(frame:NSRect(x:58,y:40,width:390,height:26),pullsDown:false)
    let formats:[CopyFormat]
    private weak var panel:NSSavePanel?
    private let rate:Double,channels:Int,source:SourceEncoding?
    private var previousExtension:String
    var format:CopyFormat {formats[popup.indexOfSelectedItem]}
    var encoding:SourceEncoding {format.encoding(rate:rate,channels:channels,source:source)}
    init(panel:NSSavePanel,rate:Double,channels:Int,source:SourceEncoding?,frames:Int=Int.max) {
        self.panel=panel;self.rate=rate;self.channels=channels;self.source=source
        formats=CopyFormat.allCases.filter{$0.isAvailable(rate:rate,source:source,frames:frames)}
        previousExtension=source?.fileExtension ?? "wav"
        super.init()
        let label=NSTextField(labelWithString:"格式：");label.frame=NSRect(x:8,y:44,width:50,height:20)
        popup.addItems(withTitles:formats.map{$0.title(rate:rate,channels:channels,source:source)})
        if source==nil,let index=formats.firstIndex(of:.wav24) {popup.selectItem(at:index)}
        popup.target=self;popup.action=#selector(changed(_:));popup.setAccessibilityLabel("副本音频格式")
        let detail=NSTextField(wrappingLabelWithString:"保留 \(String(format:"%g",rate/1000)) kHz · \(channels==1 ? "单声道" : "立体声")。"+(rate>48000 ? "此采样率提供无损格式，AAC/MP3 需降低采样率。" : "仅列出适合当前采样率和长度的格式，源文件不变。"))
        detail.frame=NSRect(x:58,y:2,width:390,height:34);detail.textColor = .secondaryLabelColor;detail.font = .systemFont(ofSize:11)
        view.addSubview(label);view.addSubview(popup);view.addSubview(detail)
        panel.accessoryView=view
        panel.allowsOtherFileTypes=false;panel.isExtensionHidden=false;panel.canSelectHiddenExtension=false
        changed(popup)
    }
    @objc func changed(_ sender:NSPopUpButton) {
        guard let panel=panel else{return}
        let ext=encoding.fileExtension,old=panel.nameFieldStringValue
        let base=(old as NSString).pathExtension.lowercased()==previousExtension.lowercased() ? (old as NSString).deletingPathExtension : old
        panel.allowedContentTypes=[UTType(filenameExtension:ext) ?? .audio]
        panel.nameFieldStringValue=base+"."+ext
        previousExtension=ext
    }
}
