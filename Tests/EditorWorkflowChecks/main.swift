import AppKit
import AudioCore

let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
var failures=0,checks=0
func check(_ condition:Bool,_ label:String) {checks += 1;if !condition {failures += 1};print("\(condition ? "PASS" : "FAIL") \(label)")}
func settle(_ model:EditorModel) {
    let deadline=Date().addingTimeInterval(10)
    while model.busy && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
    check(!model.busy,"operation completed within timeout")
}
do {
    let cache=try AudioCache(),model=EditorModel(cache:try AudioCache())
    model.monitorMuted=true
    let notesURL=cache.folder.appendingPathComponent("UI-notes.md"),notes=UsageNotesWindow(store:try UsageNotesStore(url:notesURL,version:"0.4.0"))
    let notesScroll=notes.view.subviews.compactMap{$0 as? NSScrollView}.first!,notesText=notesScroll.documentView as! NSTextView
    check(notesText.textStorage != nil && notesText.layoutManager != nil && notesText.isEditable,"notes editor has a complete editable text system")
    notesText.string="中文记录 · 关闭保存"
    check(try notes.save() && UsageNotesStore(url:notesURL,version:"0.4.1").text=="中文记录 · 关闭保存","notes UI text persists and survives an app version update")
    let asset=try cache.makeAsset(rate:48000,channels:2,frames:48000*6) {start,count in
        let a=(0..<count).map {i -> Float in Float(sin(Double(start+i)*0.057))*((start+i)<240000 ? 0.25 : 0.5)}
        return [a,a.map{$0*0.5}]
    }
    let seed=AudioDocument(rate:48000,channels:2,pieces:[Piece(asset:asset,offset:0,count:asset.frames)])
    let original=cache.folder.appendingPathComponent("源文件.wav")
    try FileAudioWriter.write(seed,to:original,encoding:.wav(rate:48000,channels:2,bits:32,isFloat:true))
    model.openURL(original);settle(model)
    let doc=model.audio
    check(model.sourceFile?.url==original && !model.dirty,"file opening retains source URL and actual encoding")
    let waveform=WaveformNSView(frame:NSRect(x:0,y:0,width:1000,height:360));waveform.model=model
    let pointer=waveform.left+waveform.plotWidth*0.37,anchor=Double(doc.frames)*0.37
    waveform.navigateWheel(deltaX:0,deltaY:4,precise:false,shift:false,pointerX:pointer)
    check(abs(model.visibleLength-Double(doc.frames)/2)<1e-8 && abs((anchor-model.visibleStart)/model.visibleLength-0.37)<1e-12,"ordinary wheel zooms horizontally at pointer without a modifier")
    waveform.navigateWheel(deltaX:0,deltaY:-4,precise:false,shift:false,pointerX:pointer)
    check(model.visibleStart==0 && model.visibleLength==Double(doc.frames),"opposite wheel direction restores full view")
    model.visibleStart=100000.1;model.visibleLength=12.3
    let fractionalAnchor=model.visibleStart+0.37*model.visibleLength
    for _ in 0..<20 {waveform.navigateWheel(deltaX:0,deltaY:1,precise:true,shift:false,pointerX:pointer)}
    check(abs((fractionalAnchor-model.visibleStart)/model.visibleLength-0.37)<1e-9,"precise wheel keeps fractional sample position fixed over repeated events")
    let panStart=model.visibleStart,panLength=model.visibleLength
    waveform.navigateWheel(deltaX:0,deltaY:20,precise:false,shift:true,pointerX:pointer)
    check(model.visibleStart>panStart && model.visibleLength==panLength,"Shift wheel pans without changing zoom")
    let nextStart=model.visibleStart
    waveform.navigateWheel(deltaX:-20,deltaY:1,precise:true,shift:false,pointerX:pointer)
    check(model.visibleStart<nextStart && model.visibleLength==panLength,"horizontal wheel gesture pans without accidental zoom")
    check(model.selection==0..<0 && !model.dirty && model.audio.revision==doc.revision,"wheel navigation does not edit audio or selection")
    model.fit()
    var acceptsKeys=true
    let keyboard=EditorKeyboard(model:model) {_ in acceptsKeys},monitor=keyboard.monitor
    func space(repeating:Bool=false,shift:Bool=false)->NSEvent {NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:shift ? .shift : [],timestamp:0,windowNumber:0,context:nil,characters:" ",charactersIgnoringModifiers:" ",isARepeat:repeating,keyCode:49)!}
    func pump(_ seconds:Double) {let until=Date().addingTimeInterval(seconds);while Date()<until {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}}
    check(monitor(space())==nil && model.playing,"Space starts playback and consumes the event exactly once")
    for _ in 0..<8 {check(monitor(space(repeating:true))==nil && model.playing,"held Space does not toggle playback")}
    pump(1.2);check(model.playing && model.playhead>48000,"playback continues beyond first three scheduled buffers")
    check(monitor(space())==nil && !model.playing,"next distinct Space stops playback")
    acceptsKeys=false;check(monitor(space()) != nil && !model.playing,"text/modal input passes through without transport action");acceptsKeys=true
    model.select(96000..<96216)
    _=monitor(space(shift:true));pump(0.25)
    check(model.playing && model.playhead>96216 && model.selection==96000..<96216,"Shift Space plays beyond a 4.5 ms selection without changing it")
    _=monitor(space());_=monitor(space());pump(0.2)
    check(!model.playing && model.status.contains("4.50 ms"),"intentional short selection still plays and explains its duration")
    var zoom=WindowZoomState();let normal=NSRect(x:100,y:100,width:1080,height:740),visible=NSRect(x:0,y:40,width:1728,height:1050)
    check(zoom.nextFrame(current:normal,visible:visible)==visible,"maximize uses whole visible screen")
    check(zoom.nextFrame(current:visible,visible:visible)==normal,"second maximize restores original window frame")
    model.select(96000..<192000)
    let beforeGain=model.audio.samples(0..<model.audio.frames)
    for _ in 0..<12 {model.adjustSelectionGain(by:-0.5)}
    check(model.pendingSelectionGain?.decibels == -6 && model.dirty,"knob wheel accumulates one pending -6 dB edit")
    check(model.audio.samples(0..<model.audio.frames)==beforeGain && model.undoName==nil,"pending knob adjustment does not bake repeated gain or add history")
    var continued=false
    model.flushSelectionGain {continued=true};settle(model)
    check(continued && model.pendingSelectionGain==nil && model.undoName=="选区音量与边界衔接","click-away commits one undoable gain and continues action")
    let gained=model.audio.samples(0..<model.audio.frames)
    check(gained[0][96000]==beforeGain[0][96000] && gained[0][191999]==beforeGain[0][191999],"committed gain joins both boundaries at original amplitude")
    check(abs(gained[0][120000]-beforeGain[0][120000]*Float(pow(10,-6.0/20)))<1e-7,"interior gain uses final value once")
    model.undo();check(model.audio.samples(0..<model.audio.frames)==beforeGain && !model.dirty,"one undo restores all knob changes")
    model.adjustSelectionGain(by:3);model.undo()
    check(model.pendingSelectionGain==nil && !model.dirty,"undo cancels unconfirmed knob edit")
    model.adjustSelectionGain(by:-3);model.select(24000..<48000);settle(model)
    check(model.selection==24000..<48000 && model.undoName != nil,"new selection click first commits old gain then selects requested range")
    model.undo();model.select(0..<0)

    model.timeUnit = .samples;model.startText="96000";model.endText="192000";model.applySelection()
    check(model.selection==96000..<192000,"sample entry selects exact range")
    model.lengthText="1";model.applySelection(useLength:true);model.zoomSelection()
    model.moveCursor(direction:-1,extend:true);model.moveCursor(direction:-1,extend:true)
    check(model.selection==95999..<96000 && model.visibleStart==95999,"Shift reversal retains anchor and scrolls into view")
    model.startText="-1";model.applySelection();check(model.selection==95999..<96000 && model.error != nil,"invalid selection leaves document unchanged");model.error=nil
    model.select(0..<0);model.fade(inward:true)
    check(model.audio.revision==doc.revision && model.undoName==nil,"fade requires explicit selection")
    model.previewEffect(.normalize(-3),name:"test");settle(model)
    check(model.isPreviewing && model.playing,"preview starts through real playback engine (monitor muted)")
    model.pauseResume();check(model.paused && !model.playing,"pause retains playback session")
    model.togglePlay();check(!model.paused && !model.playing && model.playhead==0,"Space semantics stop preview at selection start")
    check(model.audio.revision==doc.revision && model.undoName==nil && !model.dirty,"preview leaves audio revision, history and dirty state unchanged")
    model.select(96000..<192000);model.effect(.normalize(-3),name:"normalize");settle(model)
    check(model.dirty && model.undoName != nil,"applying effect creates unsaved undoable edit")
    let peak=model.audio.peak(96000..<192000,channel:0).high
    check(abs(20*log10(peak)+3)<0.01,"applied selection reaches -3 dBFS")
    check(model.audio.samples(0..<100)==doc.samples(0..<100),"effect leaves outside selection unchanged")
    model.undo();check(!model.dirty && model.selection==96000..<192000,"undo restores saved revision and selection")
    model.addMarker();model.renameMarker(model.audio.markers[0],name:"主歌入口")
    check(!model.dirty,"temporary markers do not require saving audio")
    model.effect(.gain(-6),name:"gain");settle(model)
    let before=try Data(contentsOf:original),copy=cache.folder.appendingPathComponent("副本.wav")
    model.writeCopy(to:copy);settle(model)
    check(!model.dirty && model.sourceFile?.url==original && model.lastSavedURL==copy,"saving copy completes work while retaining original source target")
    check(try Data(contentsOf:original)==before,"save-copy does not change source bytes")
    check(try cache.read(copy).frames==doc.frames,"save-copy writes entire file despite a selection")
    check(try SourceEncoding(inspecting:copy).bits==32,"copy preserves original float WAV encoding")
    model.effect(.gain(1),name:"gain");settle(model);let expected=model.audio.samples(0..<model.audio.frames)
    model.overwriteOriginal();settle(model)
    check(!model.dirty && model.sourceFile?.url==original,"overwrite updates saved state and source identity")
    try model.sourceFile?.assertUnchanged()
    check(try cache.read(original).samples(0..<doc.frames)==expected,"overwrite saves all edited samples in source encoding")
    model.openURL(original);settle(model)
    check(model.audio.markers.isEmpty && model.selection==0..<0,"reopening is a fresh file session with no project state")
    model.effect(.gain(3),name:"gain");settle(model)
    try Data("external modification".utf8).write(to:original)
    model.overwriteOriginal();settle(model)
    check(model.dirty && model.sourceFile?.url==original && model.error != nil,"changed source blocks overwrite and retains current edits")
    check(try String(contentsOf:original)=="external modification","failed overwrite preserves externally changed file")
    model.error=nil;let rescue=cache.folder.appendingPathComponent("rescue.wav")
    model.writeCopy(to:rescue);settle(model)
    check(!model.dirty && FileManager.default.fileExists(atPath:rescue.path),"save-copy can rescue edits after source changed outside app")
    let promised=SelectionFilePromise(audio:doc,range:48000..<96000,gain:nil,name:"测试源.wav")
    let provider=NSFilePromiseProvider(fileType:"com.microsoft.waveform-audio",delegate:promised)
    let destination=cache.folder.appendingPathComponent(promised.filePromiseProvider(provider,fileNameForType:"com.microsoft.waveform-audio"))
    var promiseDone=false,promiseError:Error?
    promised.operationQueue(for:provider).addOperation {
        promised.filePromiseProvider(provider,writePromiseTo:destination) {error in DispatchQueue.main.async {promiseError=error;promiseDone=true}}
    }
    let deadline=Date().addingTimeInterval(10)
    while !promiseDone && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
    check(promiseDone && promiseError==nil,"native file promise callback writes target WAV successfully")
    let promisedFormat=try SourceEncoding(inspecting:destination),promisedAudio=try cache.read(destination)
    check(promisedFormat.rate==48000 && promisedFormat.bits==24 && promisedFormat.channels==2 && promisedAudio.frames==48000,"promised drop file is 48k 24bit stereo with exact selected duration")
    check(promisedAudio.samples(0..<1)[0][0]==0 && promisedAudio.samples(47999..<48000)[0][0]==0,"promised drop includes faded endpoints")
    model.stop()
} catch {failures += 1;print("FAIL unexpected: \(error)")}
print("\(checks) workflow assertions, \(failures) failures")
exit(failures==0 ? 0 : 1)
