import AppKit
import SwiftUI
import AVFoundation
import AudioCore
import UniformTypeIdentifiers

final class EditorModel: ObservableObject {
    @Published var selectionGainDB=0.0
    @Published var pendingSelectionGain:SelectionGain?
    @Published var activeDragExports=0
    var gainControlContains:((NSPoint)->Bool)?
    @Published var showingUsageNotes=false
    var usageNotesView:NSView?
    var showUsageNotes:(()->Void)?
    var importUsageNotes:((URL)->Void)?
    @Published var startText = "0.000"
    @Published var endText = "0.000"
    @Published var renameID: UUID?
    @Published var markerName = ""
    @Published var state = EditorSnapshot()
    @Published var timeUnit = TimeUnit.clock
    @Published var lengthText = ""
    @Published var sourceFile:SourceAudioFile?
    @Published var lastSavedURL:URL?
    @Published var normalizeDB = -1.0
    @Published var silenceSeconds = 1.0
    @Published var showNormalize = false
    @Published var showSilence = false
    @Published var isPreviewing = false
    @Published var sourceMeter = SourceMeter()
    @Published var monitorMuted = false { didSet { updateMonitor() } }
    @Published var inspectorTab = 0
    var focusWaveform: (() -> Void)?
    private var keyboardSelection: SelectionGesture?
    private var playbackOrigin = 0
    private var lastMeterElapsed = 0
    @Published var name = "未命名音频"
    @Published var busy = false
    @Published var panelPresented = false
    @Published var status = "打开一段音频，开始剪辑"
    @Published var error: String?
    @Published var playing = false
    @Published var paused = false
    @Published var recording = false
    @Published var loop = false
    @Published var playhead = 0
    @Published var visibleStart = 0.0
    @Published var visibleLength = 1.0
    @Published var verticalScale = 1.0
    @Published var outputVolume: Float = 1 { didSet { updateMonitor() } }
    @Published var meter: Float = 0
    @Published var recordingSeconds = 0.0
    @Published var gainDB = 0.0
    @Published var historyVersion = 0
    @Published var followPlayback = true
    private(set) var cache: AudioCache
    private var history = EditHistory()
    private var savedRevision = UUID()
    private var clipboard: AudioDocument?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var timer: Timer?
    private var generation = UUID()
    private var playbackAudio = AudioDocument()
    private var playRange = 0..<0
    private var scheduledFrame = 0
    private var outstanding = 0
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var previousView: (Double,Double)?
    var afterSave: (() -> Void)?
    var audio: AudioDocument { state.audio }
    var selection: Range<Int> { state.selection }
    var effectiveRange: Range<Int> { selection.isEmpty ? 0..<audio.frames : selection }
    var hasAudio: Bool { audio.frames > 0 }
    var canEdit: Bool { !busy && !recording && !panelPresented }
    var dirty: Bool { audio.revision != savedRevision || pendingSelectionGain != nil }
    var undoName: String? { history.undoName }
    var redoName: String? { history.redoName }
    init(cache: AudioCache) {
        self.cache=cache; savedRevision=state.audio.revision
        history=EditHistory(state)
        syncSelectionText()
        engine.attach(player)
        timer=Timer.scheduledTimer(withTimeInterval:0.035,repeats:true) { [weak self] _ in self?.tick() }
    }
    func select(_ range: Range<Int>) {
        if flushSelectionGain({self.select(range)}) {return}
        guard canEdit else { return }
        if playing || paused { stop() }
        let start=max(0,min(audio.frames,range.lowerBound)), end=max(start,min(audio.frames,range.upperBound))
        state.selection=start..<end; history.select(state.selection); playhead=start; keyboardSelection=nil; syncSelectionText()
    }
    func commit(_ document: AudioDocument, selection: Range<Int>, name: String, keepPlayback: Bool = false) {
        if !keepPlayback { stop() }; history.commit(EditorSnapshot(audio:document,selection:selection),name:name)
        state=history.state; historyVersion += 1; if !playing && !paused { playhead=selection.lowerBound }; clampView(); status="已\(name) · 可撤销"; syncSelectionText(); focusWaveform?()
    }
    func undo() { if pendingSelectionGain != nil {cancelSelectionGain();return};guard canEdit else{return}; stop(); history.undo(); state=history.state; historyVersion += 1; playhead=selection.lowerBound; clampView(); status="已撤销";syncSelectionText();focusWaveform?() }
    func redo() { if flushSelectionGain({self.redo()}) {return};guard canEdit else{return}; stop(); history.redo(); state=history.state; historyVersion += 1; playhead=selection.lowerBound; clampView(); status="已重做";syncSelectionText();focusWaveform?() }
    func replaceDocument(_ document: AudioDocument, name: String, edited: Bool = false) {
        stop();pendingSelectionGain=nil;selectionGainDB=0; state=EditorSnapshot(audio:document); history=EditHistory(state); historyVersion += 1
        sourceFile=nil; lastSavedURL=nil; playhead=0; verticalScale=1; previousView=nil; sourceMeter.reset(); keyboardSelection=nil; syncSelectionText()
        self.name=name; savedRevision=edited ? UUID() : document.revision; fit(); status="\(name) · \(document.channels == 1 ? "单声道" : "立体声")"
    }
    func newDocument(channels: Int) {
        guard canEdit else{return}; confirmDiscard { self.replaceDocument(AudioDocument(channels:channels),name:"未命名音频") }
    }
    func confirmDiscard(_ action: @escaping () -> Void) {
        if flushSelectionGain({self.confirmDiscard(action)}) {return}
        guard dirty else { action(); return }
        let alert=NSAlert();alert.messageText="当前音频有未保存的修改"
        alert.informativeText=sourceFile.map {"写入 \($0.url.lastPathComponent) 后再继续，或放弃本次修改。"} ?? "可以先保存为 WAV 副本，再继续。"
        alert.addButton(withTitle:sourceFile == nil ? "保存为 WAV 副本" : "写入并覆盖原文件");alert.addButton(withTitle:"取消");alert.addButton(withTitle:"放弃修改")
        switch alert.runModal() {
        case .alertFirstButtonReturn:afterSave=action;if sourceFile != nil {overwriteOriginal()} else {saveCopy()}
        case .alertThirdButtonReturn: action()
        default: break
        }
    }
    func openPanel() {
        guard canEdit else{return}
        confirmDiscard {
            let panel=NSOpenPanel(); panel.allowedContentTypes=[.audio]; panel.allowsMultipleSelection=false
            self.presentFilePanel(panel) {url in if let url=url {self.load(url)}}
        }
    }
    func openURL(_ url: URL) { guard canEdit else{return}; confirmDiscard { self.load(url) } }
    private func load(_ url:URL) {
        stop();let cache=self.cache
        perform("正在读取音频…",job:{ () -> (AudioDocument,SourceAudioFile) in
            let source=try SourceAudioFile(url),doc=try cache.read(source.url)
            try source.assertUnchanged();return (doc,source)
        }) {doc,source in
            self.replaceDocument(doc,name:source.url.lastPathComponent)
            self.sourceFile=source
            NSDocumentController.shared.noteNewRecentDocumentURL(source.url);self.focusWaveform?()
        }
    }

    func demo() {
        guard canEdit else{return}
        confirmDiscard {
            let cache=self.cache
            self.perform("正在生成示例音频…",job: { () -> AudioDocument in
                let rate=48000.0, frames=Int(rate*18)
                let asset=try cache.makeAsset(rate:rate,channels:2,frames:frames) { start,count in
                    var data=[[Float]](repeating:[Float](repeating:0,count:count),count:2)
                    let notes=[220.0,261.6256,329.6276,293.6648,246.9417,196.0]
                    for i in 0..<count {
                        let t=Double(start+i)/rate, beat=t.truncatingRemainder(dividingBy:0.5)
                        let freq=notes[min(5,Int(t/3))]
                        let envelope=min(1,t/0.08)*min(1,(18-t)/1.8)
                        let pulse=exp(-beat*8)*0.5+0.2
                        for c in 0..<2 {
                            let tone=sin(2*Double.pi*freq*t)+0.34*sin(2*Double.pi*freq*2*t+Double(c)*0.22)
                            data[c][i]=Float(tone*pulse*envelope*0.48)
                        }
                    }; return data
                }
                var doc=AudioDocument(rate:rate,channels:2,pieces:[Piece(asset:asset,offset:0,count:frames)])
                doc.markers=[AudioMarker(frame:0,name:"开始"),AudioMarker(frame:288000,name:"第二段"),AudioMarker(frame:576000,name:"尾段")]
                return doc
            }) { self.replaceDocument($0,name:"晨间片段 · 合成示例",edited:true) }
        }
    }
    func perform<T>(_ label: String, job: @escaping () throws -> T, done: @escaping (T) -> Void) {
        busy=true; status=label
        DispatchQueue.global(qos:.userInitiated).async {
            let result=Result { try job() }
            DispatchQueue.main.async {
                self.busy=false
                switch result { case .success(let value): done(value); case .failure(let err): self.error=err.localizedDescription; self.status="操作未完成"; self.afterSave=nil }
            }
        }
    }
    func copy() { if flushSelectionGain({self.copy()}) {return}; guard canEdit,!selection.isEmpty else{return}; var clip=audio; clip.pieces=audio.sliced(selection); clip.markers=[]; clipboard=clip; status="已复制 \(time(Double(selection.count)/audio.rate))";focusWaveform?() }
    func cut() { if flushSelectionGain({self.cut()}) {return}; guard !selection.isEmpty else{return}; copy(); deleteSelection("剪切") }
    func deleteSelection(_ name: String = "删除") {
        if flushSelectionGain({self.deleteSelection(name)}) {return}
        guard canEdit,!selection.isEmpty else{return};stop()
        let doc=audio,range=selection,cache=self.cache
        perform("正在\(name)并平滑衔接…",job:{try SmoothDeletion.apply(doc,range:range,cache:cache)}) {result in
            self.commit(result.audio,selection:result.cursor..<result.cursor,name:name)
        }
    }
    var canPaste: Bool { clipboard != nil && canEdit }
    func paste() {
        if flushSelectionGain({self.paste()}) {return}
        guard canEdit,let clip=clipboard else{return}
        guard clip.rate==audio.rate,clip.channels==audio.channels else { error="当前版本仅支持相同采样率和声道数的粘贴。"; return }
        let end=selection.lowerBound+clip.frames
        commit(audio.replacing(selection,with:clip.pieces),selection:selection.lowerBound..<end,name:"粘贴")
    }
    func crop() { if flushSelectionGain({self.crop()}) {return}; guard canEdit,!selection.isEmpty else{return}; let count=selection.count; commit(audio.cropped(selection),selection:0..<count,name:"裁剪"); fit() }
    func effect(_ effect: Effect, name: String) {
        if flushSelectionGain({self.effect(effect,name:name)}) {return}
        guard canEdit,hasAudio else{return}; stop()
        let doc=audio,range=effectiveRange,sel=selection,cache=self.cache
        perform("正在\(name)…",job:{ try doc.transformed(range,effect:effect,cache:cache) }) { self.commit($0,selection:sel,name:name) }
    }
    func insertSilence(seconds: Double = 1) {
        if flushSelectionGain({self.insertSilence(seconds:seconds)}) {return}
        guard canEdit else{return}
        guard seconds.isFinite,seconds>0,seconds<=3600 else {error="静音时长请输入大于 0 且不超过 3600 秒的数值。";return}
        guard seconds*audio.rate>=1 else {error="静音时长至少为一个样本帧。";return}
        stop(); let doc=audio,sel=selection,cache=self.cache,frames=Int((seconds*audio.rate).rounded())
        perform("正在插入静音…",job:{ try cache.makeAsset(rate:doc.rate,channels:doc.channels,frames:frames) { _,count in [[Float]](repeating:[Float](repeating:0,count:count),count:doc.channels) } }) { asset in
            self.commit(doc.replacing(sel,with:[Piece(asset:asset,offset:0,count:asset.frames)]),selection:sel.lowerBound..<sel.lowerBound+frames,name:"插入 \(String(format:"%.3f",seconds)) 秒静音")
        }
    }
    func addMarker() {
        if flushSelectionGain({self.addMarker()}) {return}
        guard canEdit,hasAudio else{return}; var doc=audio
        doc.markers.append(AudioMarker(frame:(playing || paused) ? playhead : selection.lowerBound,name:"标记 \(doc.markers.count+1)"))
        doc.markers.sort{$0.frame < $1.frame}; commit(doc,selection:selection,name:"添加标记",keepPlayback:true)
    }
    func deleteMarker(_ marker: AudioMarker) { if flushSelectionGain({self.deleteMarker(marker)}) {return};guard canEdit else{return}; var doc=audio; doc.markers.removeAll{$0.id==marker.id}; commit(doc,selection:selection,name:"删除标记",keepPlayback:true) }
    func renameMarker(_ marker: AudioMarker, name: String) { if flushSelectionGain({self.renameMarker(marker,name:name)}) {return};guard canEdit else{return}; var doc=audio; guard let index=doc.markers.firstIndex(where:{$0.id==marker.id}) else{return}; doc.markers[index].name=name; commit(doc,selection:selection,name:"标记改名",keepPlayback:true) }
    func fit() { previousView=(visibleStart,visibleLength); visibleStart=0; visibleLength=Double(max(1,audio.frames)) }
    func zoom(_ factor: Double, anchor: Double? = nil) {
        guard hasAudio,canEdit else{return}; previousView=(visibleStart,visibleLength)
        let point=anchor ?? Double(playing || paused ? playhead : selection.lowerBound)
        let focus=(point>=visibleStart && point<=visibleStart+visibleLength) ? point : visibleStart+visibleLength/2
        let v=Viewport(start:visibleStart,length:visibleLength).zoomed(factor:factor,anchor:focus,total:Double(audio.frames))
        visibleStart=v.start;visibleLength=v.length
    }
    func zoomSelection() { guard !selection.isEmpty else{return}; previousView=(visibleStart,visibleLength); visibleStart=Double(selection.lowerBound); visibleLength=Double(max(1,selection.count)); clampView() }
    func restoreView() { if let p=previousView { previousView=(visibleStart,visibleLength); visibleStart=p.0; visibleLength=p.1; clampView() } }
    func clampView() { visibleLength=max(1,min(Double(max(1,audio.frames)),visibleLength)); visibleStart=max(0,min(Double(audio.frames)-visibleLength,visibleStart)) }
    func pan(_ frames: Double) { visibleStart += frames; clampView() }
    func togglePlay(ignoreSelection:Bool=false) {
        if recording {stopRecording();return}
        guard canEdit,hasAudio else{return}
        focusWaveform?()
        if playing || paused {stop();return}
        if ignoreSelection {
            let start=selection.lowerBound>=audio.frames ? 0 : selection.lowerBound
            startPlayback(range:start..<audio.frames,from:start)
        } else {startPlayback()}
    }
    func pauseResume() {
        guard canEdit else{return};focusWaveform?()
        if playing {player.pause();playing=false;paused=true;sourceMeter.stop();status="已暂停 · 逗号继续"}
        else if paused {player.play();playing=true;paused=false;status=isPreviewing ? "效果预听中 · 尚未应用" : "正在播放"}
    }
    private func startPlayback(document: AudioDocument? = nil, range: Range<Int>? = nil, from: Int? = nil, preview: Bool = false) {
        stop(); playbackAudio=document ?? audio
        let start=selection.lowerBound >= audio.frames ? 0 : selection.lowerBound
        playRange=range ?? (selection.isEmpty ? start..<audio.frames : selection)
        guard !playRange.isEmpty else{return}
        scheduledFrame=max(playRange.lowerBound,min(playRange.upperBound-1,from ?? playRange.lowerBound))
        playbackOrigin=scheduledFrame;playhead=scheduledFrame;lastMeterElapsed=0;isPreviewing=preview
        let format=AVAudioFormat(standardFormatWithSampleRate:playbackAudio.rate,channels:AVAudioChannelCount(playbackAudio.channels))!
        engine.disconnectNodeOutput(player);engine.connect(player,to:engine.mainMixerNode,format:format)
        do {try engine.start();updateMonitor();fillPlayback();player.play();playing=true;status=preview ? "效果预听中 · 尚未应用" : "正在播放"}
        catch {stop();self.error=error.localizedDescription}
    }
    private func fillPlayback() {
        while outstanding < 3 {
            if scheduledFrame >= playRange.upperBound {
                if loop { scheduledFrame=playRange.lowerBound } else { break }
            }
            let shortLoop = loop && playRange.count < 2048
            let bufferCount = shortLoop ? 2048 : min(2048,playRange.upperBound-scheduledFrame)
            let end=scheduledFrame+bufferCount
            let format=AVAudioFormat(standardFormatWithSampleRate:playbackAudio.rate,channels:AVAudioChannelCount(playbackAudio.channels))!
            let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(end-scheduledFrame))!
            buffer.frameLength=buffer.frameCapacity
            var block: [[Float]]
            if shortLoop {
                let cycle=playbackAudio.samples(playRange)
                let offset=scheduledFrame-playRange.lowerBound
                block=cycle.map { channel in (0..<bufferCount).map { channel[(offset+$0)%playRange.count] } }
            } else { block=playbackAudio.samples(scheduledFrame..<end) }
            if let gain=pendingSelectionGain,!isPreviewing,playbackAudio.revision==audio.revision {
                for i in 0..<bufferCount {
                    let f=shortLoop ? playRange.lowerBound+(scheduledFrame-playRange.lowerBound+i)%playRange.count : scheduledFrame+i
                    let multiplier=gain.multiplier(at:f,rate:playbackAudio.rate)
                    for c in 0..<playbackAudio.channels {block[c][i] *= multiplier}
                }
            }
            for c in 0..<playbackAudio.channels { block[c].withUnsafeBufferPointer { buffer.floatChannelData![c].update(from:$0.baseAddress!,count:block[c].count) } }
            scheduledFrame = shortLoop ? playRange.lowerBound+(end-playRange.lowerBound)%playRange.count : end
            outstanding += 1; let token=generation
            player.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self=self,self.generation==token else{return}
                    self.outstanding -= 1; self.fillPlayback()
                    if self.outstanding==0 {
                        let duration=Double(self.playRange.count)/self.playbackAudio.rate
                        self.stop()
                        self.status=duration<0.02 ? "选区仅 \(String(format:"%.2f",duration*1000)) ms，已播完 · ⇧空格可从光标继续播放" : "播放结束"
                    }
                }
            }
        }
    }
    func stop() {
        if recording { stopRecording(); return }
        let wasActive=playing || paused
        generation=UUID(); player.stop(); engine.stop(); outstanding=0; playing=false; paused=false; meter=0; sourceMeter.stop(); isPreviewing=false;playbackAudio=AudioDocument();playhead=selection.lowerBound
        if wasActive { status="已停止" }
    }
    func toggleLoop() {
        guard canEdit else{return}
        let active=playing || paused,wasPaused=paused,position=playhead,doc=playbackAudio,range=playRange,preview=isPreviewing
        stop();loop.toggle()
        if active {startPlayback(document:doc,range:range,from:position,preview:preview);if wasPaused {pauseResume()}}
        focusWaveform?()
    }
    private func tick() {
        if recording,let recorder=recorder {
            recorder.updateMeters();recordingSeconds=recorder.currentTime
            sourceMeter.ingest((0..<audio.channels).map {pow(10,recorder.peakPower(forChannel:$0)/20)})
            return
        }
        guard playing,let render=player.lastRenderTime,let time=player.playerTime(forNodeTime:render) else{return}
        let elapsed=max(0,Int(time.sampleTime)),count=max(1,playRange.count)
        let position=playbackOrigin-playRange.lowerBound+elapsed
        playhead=loop ? playRange.lowerBound+position%count : min(playRange.upperBound,playbackOrigin+elapsed)
        let previous=playbackOrigin-playRange.lowerBound+lastMeterElapsed
        let ranges:[Range<Int>]
        if loop && elapsed-lastMeterElapsed>=count {ranges=[playRange]}
        else if loop {
            let a=playRange.lowerBound+previous%count,b=playhead
            ranges=b<a ? [a..<playRange.upperBound,playRange.lowerBound..<b] : [a..<b]
        } else {ranges=[min(playRange.upperBound,playbackOrigin+lastMeterElapsed)..<playhead]}
        sourceMeter.ingest((0..<playbackAudio.channels).map { c in
            ranges.reduce(Float(0)) { result,r in let p=playbackAudio.peak(r,channel:c);return max(result,abs(p.low),abs(p.high)) }
        })
        lastMeterElapsed=elapsed
        if followPlayback && (Double(playhead)>visibleStart+visibleLength || Double(playhead)<visibleStart) {visibleStart=Double(playhead);clampView()}
    }
    func record() {
        if flushSelectionGain({self.record()}) {return}
        if recording { stopRecording(); return }; guard canEdit else{return}; stop(); busy=true; status="正在检查录音权限…"
        AVCaptureDevice.requestAccess(for:.audio) { granted in DispatchQueue.main.async {
            self.busy=false
            guard granted else { self.error="请在系统设置 → 隐私与安全性 → 麦克风中允许声刻使用麦克风。"; self.status="麦克风未授权"; return }
            self.beginRecording()
        } }
    }
    private func beginRecording() {
        do {
            let url=cache.folder.appendingPathComponent("recording-\(UUID().uuidString).caf")
            let settings:[String:Any]=[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:audio.rate,AVNumberOfChannelsKey:audio.channels,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true]
            let rec=try AVAudioRecorder(url:url,settings:settings); rec.isMeteringEnabled=true
            guard rec.prepareToRecord(),rec.record() else { throw AudioError.invalid("无法启动录音，请检查系统输入设备。") }
            recorder=rec; recordingURL=url; recording=true; recordingSeconds=0;sourceMeter.reset(); status="录音中 · 点击停止完成"
        } catch { self.error=error.localizedDescription }
    }
    func stopRecording() {
        guard recording,let url=recordingURL else{return}; recorder?.stop(); recorder=nil; recording=false; recordingURL=nil; meter=0;sourceMeter.stop()
        let cache=self.cache,doc=audio,sel=selection
        perform("正在整理录音…",job:{ try cache.read(url) }) { recorded in
            guard recorded.rate==doc.rate,recorded.channels==doc.channels else { self.error="录音设备返回的格式与文档不一致。原始录音保留在 \(url.path)"; return }
            self.commit(doc.replacing(sel,with:recorded.pieces),selection:sel.lowerBound..<sel.lowerBound+recorded.frames,name:"录音")
            try? FileManager.default.removeItem(at:url)
            self.fit()
        }
    }
    private func presentFilePanel(_ panel:NSSavePanel,completion:@escaping(URL?)->Void) {
        panelPresented=true
        let finish:(NSApplication.ModalResponse)->Void = {response in
            self.panelPresented=false;completion(response == .OK ? panel.url : nil)
        }
        if let window=NSApp.mainWindow {panel.beginSheetModal(for:window,completionHandler:finish)}
        else {finish(panel.runModal())}
    }
}
func time(_ seconds: Double) -> String {
    guard seconds.isFinite else{return "00:00:00.000"}
    let ms=max(0,Int((seconds*1000).rounded()))
    return String(format:"%02d:%02d:%02d.%03d",ms/3600000,(ms/60000)%60,(ms/1000)%60,ms%1000)
}

extension EditorModel {
    func updateMonitor() {player.volume=monitorMuted ? 0 : outputVolume}
    func syncSelectionText() {
        startText=timeUnit.format(selection.lowerBound,rate:audio.rate)
        endText=timeUnit.format(selection.upperBound,rate:audio.rate)
        lengthText=timeUnit.format(selection.count,rate:audio.rate)
    }
    func applySelection(useLength:Bool=false) {
        do {
            let a=try timeUnit.parse(startText,rate:audio.rate)
            let b:Int
            if useLength {let length=try timeUnit.parse(lengthText,rate:audio.rate);guard length<=audio.frames,a<=audio.frames-length else {throw AudioError.invalid("选区超出音频范围。")};b=a+length}
            else {b=try timeUnit.parse(endText,rate:audio.rate)}
            guard a<=b,b<=audio.frames else {throw AudioError.invalid("选区需满足：0 ≤ 起点 ≤ 终点 ≤ 音频长度。")}
            select(a..<b);focusWaveform?()
        } catch {self.error=error.localizedDescription}
    }
    func moveCursor(direction:Int,extend:Bool) {
        guard canEdit else{return}
        let step=max(1,Int(visibleLength/900))
        if extend {
            var gesture=keyboardSelection ?? SelectionGesture(anchor:selection.lowerBound,head:selection.upperBound)
            gesture.move(by:direction*step,limit:audio.frames)
            select(gesture.range);keyboardSelection=gesture;playhead=gesture.head
        } else {
            let position=selection.isEmpty ? max(0,min(audio.frames,playhead+direction*step)) : (direction<0 ? selection.lowerBound : selection.upperBound)
            select(position..<position)
        }
        if Double(playhead)<visibleStart {visibleStart=Double(playhead)}
        else if Double(playhead)>visibleStart+visibleLength {visibleStart=Double(playhead)-visibleLength}
        clampView()
    }
    func centerSelection(end:Bool) {visibleStart=Double(end ? selection.upperBound : selection.lowerBound)-visibleLength/2;clampView()}
    func goToMarker(next:Bool) {
        guard canEdit else{return}
        let positions=audio.markers.map(\.frame).sorted()
        let f=next ? (positions.first{$0>playhead} ?? audio.frames) : (positions.last{$0<playhead} ?? 0)
        select(f..<f);visibleStart=Double(f)-visibleLength/2;clampView();focusWaveform?()
    }
    func stopAtPlayhead() {let position=playhead;stop();select(position..<position);focusWaveform?()}
    func playFrom(_ frame:Int) {
        guard canEdit,hasAudio else{return}
        let inside=selection.contains(frame)
        startPlayback(range:inside ? selection : 0..<audio.frames,from:frame);focusWaveform?()
    }
    func fade(inward:Bool) {
        guard !selection.isEmpty else {status="请先选择淡入或淡出的范围（全段可按 ⌘A）";return}
        effect(inward ? .fadeIn : .fadeOut,name:inward ? "淡入" : "淡出")
    }
    func previewEffect(_ effect:Effect,name:String) {
        guard canEdit,hasAudio else{return}
        stop();let doc=audio,range=effectiveRange,cache=self.cache
        let previewRange=range.lowerBound..<min(range.upperBound,range.lowerBound+Int(audio.rate*5))
        // Normalize against the whole intended range, even though the audition is limited to five seconds.
        var previewEffect=effect
        if case .normalize(let db)=effect {
            guard db.isFinite,(-96...0).contains(db) else {error="归一化目标应为 -96 到 0 dBFS。";return}
            let maximum:Float=(0..<doc.channels).map {c -> Float in let p=doc.peak(range,channel:c);return max(abs(p.low),abs(p.high))}.max() ?? 0
            if maximum==0 {previewEffect = .gain(0)}
            else {
                let dbGain=db-20*log10(Double(maximum))
                if !(-96...48).contains(dbGain) {error="该预听需要超过支持范围的增益，请先检查静音或极低电平音频。";return}
                previewEffect = .gain(dbGain)
            }
        }
        perform("正在准备 \(name) 试听…",job:{try doc.transformed(previewRange,effect:previewEffect,cache:cache)}) { preview in
            self.startPlayback(document:preview,range:previewRange,preview:true);self.focusWaveform?()
        }
    }
    var sourceEncoding:SourceEncoding {sourceFile?.encoding ?? .wav(rate:audio.rate,channels:audio.channels)}
    func overwriteOriginal() {
        if flushSelectionGain({self.overwriteOriginal()}) {return}
        guard canEdit,hasAudio,let source=sourceFile else{return};stop();let doc=audio
        perform("正在写入原文件…",job:{
            try FileAudioWriter.write(doc,to:source.url,encoding:source.encoding,overwriting:source)
            return try SourceAudioFile(source.url)
        }) {saved in
            self.sourceFile=saved;self.completeSave(revision:doc.revision,url:saved.url,message:"已写入原文件 · \(saved.encoding.description)")
        }
    }
    func saveCopy() {
        if flushSelectionGain({self.saveCopy()}) {return}
        guard canEdit,hasAudio else{return};stop()
        let ext=sourceEncoding.fileExtension,base=sourceFile?.url.deletingPathExtension().lastPathComponent ?? name
        let panel=NSSavePanel();panel.title="保存为副本"
        panel.directoryURL=sourceFile?.url.deletingLastPathComponent();panel.nameFieldStringValue=base+"-副本."+ext
        let accessory=SaveCopyAccessory(panel:panel,rate:audio.rate,channels:audio.channels,source:sourceFile?.encoding,frames:audio.frames)
        presentFilePanel(panel) {url in guard let url=url else {self.afterSave=nil;return};self.writeCopy(to:url,encoding:accessory.encoding)}
    }
    func writeCopy(to url:URL,encoding requested:SourceEncoding?=nil) {
        if flushSelectionGain({self.writeCopy(to:url,encoding:requested)}) {return}
        guard canEdit,hasAudio else{return};stop();let doc=audio,source=sourceFile,encoding=requested ?? sourceEncoding
        perform("正在保存副本…",job:{
            if let source=source {try FileAudioWriter.copy(doc,source:source,to:url,encoding:encoding)}
            else {try FileAudioWriter.write(doc,to:url,encoding:encoding)}
            return url
        }) {saved in self.completeSave(revision:doc.revision,url:saved,message:"已保存副本：\(saved.lastPathComponent) · 原文件未改动")}
    }
    func convertSourceToWAV() {
        if flushSelectionGain({self.convertSourceToWAV()}) {return}
        guard canEdit,hasAudio,let source=sourceFile else{return};stop();let doc=audio
        perform("正在保存 WAV 并移走源文件…",job:{try FileAudioWriter.convertToWAV(doc,source:source)}) {result in
            if let warning=result.warning {self.error=warning;self.status="WAV 已保存，源文件仍保留";self.lastSavedURL=result.file.url;return}
            self.sourceFile=result.file;self.name=result.file.url.lastPathComponent
            self.completeSave(revision:doc.revision,url:result.file.url,message:"已保存 \(result.file.url.lastPathComponent) · 源文件已移入废纸篓")
        }
    }
    private func completeSave(revision:UUID,url:URL,message:String) {
        savedRevision=revision;lastSavedURL=url;status=message
        let next=afterSave;afterSave=nil;next?();focusWaveform?()
    }
}


extension EditorModel {
    func adjustSelectionGain(by delta:Double) {
        guard canEdit,!selection.isEmpty,delta.isFinite else{return}
        let db=max(-60,min(24,selectionGainDB+delta))
        selectionGainDB=db
        pendingSelectionGain=abs(db)<0.00001 ? nil : SelectionGain(range:selection,decibels:db)
        status=String(format:"选区音量 %+.1f dB · 点击别处完成 · 边界自动衔接",db)
    }
    func cancelSelectionGain() {pendingSelectionGain=nil;selectionGainDB=0;status="已取消选区音量调整"}
    @discardableResult func flushSelectionGain(_ next:@escaping()->Void = {})->Bool {
        guard let adjustment=pendingSelectionGain else{return false}
        guard !busy else{return true}
        let source=audio,selection=selection,cache=cache
        stop();pendingSelectionGain=nil;selectionGainDB=0
        perform("正在平滑衔接选区音量…",job:{Result {try adjustment.applied(to:source,cache:cache)}}) {result in
            switch result {
            case .success(let document):self.commit(document,selection:selection,name:"选区音量与边界衔接");next()
            case .failure(let error):self.pendingSelectionGain=adjustment;self.selectionGainDB=adjustment.decibels;self.error=error.localizedDescription;self.status="音量尚未应用，请重试或撤销"
            }
        }
        return true
    }
    func acceptDroppedFile(_ url:URL) {
        if ["md","markdown"].contains(url.pathExtension.lowercased()) {importUsageNotes?(url)} else {openURL(url)}
    }
}
