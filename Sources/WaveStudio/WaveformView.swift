import AppKit
import SwiftUI
import AudioCore
import UniformTypeIdentifiers

struct WaveformSurface: NSViewRepresentable {
    @ObservedObject var model: EditorModel
    var overview = false
    func makeNSView(context: Context) -> WaveformNSView { let v=WaveformNSView(); v.model=model; v.overview=overview; if !overview { model.focusWaveform = { [weak v] in if let v=v { v.window?.makeFirstResponder(v) } } }; return v }
    func updateNSView(_ view: WaveformNSView, context: Context) { view.model=model; view.overview=overview; view.updateGainControl();view.needsDisplay=true; view.window?.invalidateCursorRects(for:view) }
}
final class WaveformNSView: NSView, NSDraggingSource {
    weak var model: EditorModel?
    var overview=false
    private let gainKnob=SelectionGainKnob(frame:NSRect(x:0,y:40,width:118,height:40))
    private var exportCandidate:Range<Int>?
    private var exportStart=NSPoint.zero
    private var fileDrag=false
    private var promises:[UUID:SelectionFilePromise]=[:]
    private var sessionPromise:UUID?
    private var anchor=0
    private var startX=0.0
    private var originalView=0.0
    private var hand=false
    private var dragX=0.0
    private var selectionDrag=SelectionDrag(startX:0)
    private var dragTimer:Timer?
    deinit {dragTimer?.invalidate()}
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) { super.init(frame:frame); setAccessibilityLabel("音频波形编辑区"); setAccessibilityRole(.group);addSubview(gainKnob);gainKnob.isHidden=true;registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    var left: Double { overview ? 8 : 48 }
    var plotWidth: Double { max(1,bounds.width-left-12) }
    func frameAt(_ x: Double) -> Int {
        guard let m=model else{return 0}
        let start=overview ? 0 : m.visibleStart, length=overview ? Double(m.audio.frames) : m.visibleLength
        return max(0,min(m.audio.frames,Int((start+(x-left)/plotWidth*length).rounded())))
    }
    func xAt(_ frame: Int) -> Double {
        guard let m=model else{return left}
        let start=overview ? 0 : m.visibleStart,length=overview ? Double(max(1,m.audio.frames)) : m.visibleLength
        return left+(Double(frame)-start)/length*plotWidth
    }
    func text(_ value: String, at point: NSPoint, color: NSColor = .secondaryLabelColor, size: CGFloat=10) {
        (value as NSString).draw(at:point,withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:size,weight:.regular),.foregroundColor:color])
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let m=model else{return}
        NSColor(calibratedRed:0.065,green:0.081,blue:0.10,alpha:1).setFill(); bounds.fill()
        guard m.hasAudio else{return}
        let top: Double=overview ? 7 : 34, bottom: Double=overview ? 7 : 8
        let lanes=overview ? 1 : m.audio.channels
        let height=(bounds.height-top-bottom)/Double(lanes)
        let start=overview ? 0 : m.visibleStart, length=overview ? Double(m.audio.frames) : m.visibleLength
        if !overview {
            let sampleRuler=length < m.audio.rate*0.01
            let options=sampleRuler ? [1.0,2,5,10,20,50,100,200,500,1000] : [0.0001,0.0002,0.0005,0.001,0.002,0.005,0.01,0.02,0.05,0.1,0.2,0.5,1,2,5,10,15,30,60,120,300,600,1800,3600]
            let units=sampleRuler ? 1.0 : m.audio.rate
            let step=options.first {$0 >= length/units/(plotWidth/110)} ?? 3600
            var tick=floor(start/units/step)*step
            while tick <= (start+length)/units {
                let x=xAt(Int((tick*units).rounded()))
                if x>=left {
                    NSColor.white.withAlphaComponent(0.065).setStroke();let p=NSBezierPath();p.move(to:NSPoint(x:x,y:24));p.line(to:NSPoint(x:x,y:bounds.height));p.stroke()
                    text(sampleRuler ? "\(Int(tick)) smp" : time(tick),at:NSPoint(x:x+5,y:8),color:NSColor.white.withAlphaComponent(0.5))
                };tick += step
            }
            let a=max(left,xAt(m.selection.lowerBound)), b=min(bounds.width-12,xAt(m.selection.upperBound))
            if b>a && !m.selection.isEmpty {
                NSColor.systemMint.withAlphaComponent(0.13).setFill(); NSRect(x:a,y:top,width:b-a,height:bounds.height-top).fill()
                NSColor.systemMint.withAlphaComponent(0.65).setStroke(); NSBezierPath(rect:NSRect(x:a,y:top,width:b-a,height:bounds.height-top-1)).stroke()
            }
        }
        for lane in 0..<lanes {
            let y=top+Double(lane)*height, center=y+height/2, amplitude=height*0.39*(overview ? 1 : m.verticalScale)
            NSColor.white.withAlphaComponent(0.12).setStroke()
            let line=NSBezierPath(); line.move(to:NSPoint(x:left,y:center)); line.line(to:NSPoint(x:bounds.width-12,y:center)); line.stroke()
            if !overview {
                text(m.audio.channels==1 ? "MONO" : lane==0 ? "L" : "R",at:NSPoint(x:12,y:y+12),color:.white.withAlphaComponent(0.6),size:11)
                for value in [0.5,-0.5] {
                    let label=String(format:"%.0f",20*log10(0.5/m.verticalScale))
                    let gy=center-value*height*0.39
                    text(label,at:NSPoint(x:12,y:gy-5),color:.white.withAlphaComponent(0.25),size:9)
                    NSColor.white.withAlphaComponent(0.035).setStroke(); let grid=NSBezierPath(); grid.move(to:NSPoint(x:left,y:gy)); grid.line(to:NSPoint(x:bounds.width-12,y:gy)); grid.stroke()
                }
            }
            let color=lane==0 ? NSColor(calibratedRed:0.36,green:0.84,blue:0.72,alpha:1) : NSColor(calibratedRed:0.43,green:0.66,blue:0.94,alpha:1)
            color.withAlphaComponent(overview ? 0.65 : 0.94).setStroke()
            let wave=NSBezierPath(); wave.lineWidth=overview ? 1 : 1.1
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:NSRect(x:left,y:y+3,width:plotWidth,height:height-6)).addClip()
            if !overview && length/plotWidth<1 {
                let first=max(0,Int(start)-1),last=min(m.audio.frames,Int(ceil(start+length))+2)
                let samples=m.audio.samples(first..<last)[lane]
                for (i,value) in samples.enumerated() {
                    let point=NSPoint(x:xAt(first+i),y:center-Double(value*(m.pendingSelectionGain?.multiplier(at:first+i,rate:m.audio.rate) ?? 1))*amplitude)
                    if i==0 {wave.move(to:point)} else {wave.line(to:point)}
                    if length<150 {color.setFill();NSBezierPath(ovalIn:NSRect(x:point.x-2,y:point.y-2,width:4,height:4)).fill()}
                }
            } else {
                for pixel in 0..<Int(plotWidth) {
                    let a=max(0,Int(start+Double(pixel)/plotWidth*length)),b=min(m.audio.frames,max(a+1,Int(start+Double(pixel+1)/plotWidth*length)))
                    guard a<b else{continue}
                    var peak=m.audio.peak(a..<b,channel:lane)
                    if overview && m.audio.channels>1 {peak.include(m.audio.peak(a..<b,channel:1))}
                    if let gain=m.pendingSelectionGain {
                        let factor=gain.multiplier(at:(a+b)/2,rate:m.audio.rate);peak.low *= factor;peak.high *= factor
                    }
                    let x=left+Double(pixel)+0.5
                    let high=max(y+4,min(y+height-4,center-Double(peak.high)*amplitude))
                    let low=max(y+4,min(y+height-4,center-Double(peak.low)*amplitude))
                    wave.move(to:NSPoint(x:x,y:high));wave.line(to:NSPoint(x:x,y:max(high+0.6,low)))
                }
            }
            wave.stroke();NSGraphicsContext.restoreGraphicsState()
        }
        for marker in m.audio.markers {
            let x=xAt(marker.frame); guard x>=left && x<=bounds.width-12 else{continue}
            NSColor.systemOrange.withAlphaComponent(0.55).setStroke(); let p=NSBezierPath(); p.move(to:NSPoint(x:x,y:top)); p.line(to:NSPoint(x:x,y:bounds.height-bottom)); p.stroke()
            if !overview { text(marker.name,at:NSPoint(x:x+5,y:top+5),color:.systemOrange,size:10) }
        }
        if overview {
            let x=xAt(Int(m.visibleStart)), w=m.visibleLength/Double(max(1,m.audio.frames))*plotWidth
            NSColor.systemMint.withAlphaComponent(0.09).setFill(); NSRect(x:x,y:2,width:max(3,w),height:bounds.height-4).fill()
            NSColor.systemMint.withAlphaComponent(0.8).setStroke(); NSBezierPath(roundedRect:NSRect(x:x,y:2,width:max(3,w),height:bounds.height-4),xRadius:3,yRadius:3).stroke()
        } else {
            if !m.selection.isEmpty {
                for f in [m.selection.lowerBound,m.selection.upperBound] {
                    let edge=xAt(f)
                    if edge>=left && edge<=bounds.width-12 {
                        NSColor.systemMint.setFill();NSBezierPath(roundedRect:NSRect(x:edge-3,y:top,width:6,height:18),xRadius:2,yRadius:2).fill()
                    }
                }
            }
            let x=xAt(m.playhead)
            if x>=left && x<=bounds.width-12 {
                NSColor.white.withAlphaComponent(0.9).setStroke(); let p=NSBezierPath(); p.move(to:NSPoint(x:x,y:top-6)); p.line(to:NSPoint(x:x,y:bounds.height)); p.stroke()
                NSColor.white.setFill(); let arrow=NSBezierPath(); arrow.move(to:NSPoint(x:x-4,y:top-7)); arrow.line(to:NSPoint(x:x+4,y:top-7)); arrow.line(to:NSPoint(x:x,y:top)); arrow.close(); arrow.fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let m=model,m.canEdit,m.hasAudio else{return}; window?.makeFirstResponder(self)
        let point=convert(event.locationInWindow,from:nil);exportCandidate=nil;fileDrag=false;exportStart=point; startX=point.x; originalView=m.visibleStart
        if overview { m.visibleStart=Double(frameAt(point.x))-m.visibleLength/2; m.clampView(); return }
        if event.clickCount==2 { m.select(0..<m.audio.frames); return }
        hand=event.modifierFlags.contains(.option)
        if hand { return }
        let frame=frameAt(point.x)
        let adjustingEdge = !m.selection.isEmpty && (event.modifierFlags.contains(.shift) || min(abs(point.x-xAt(m.selection.lowerBound)),abs(point.x-xAt(m.selection.upperBound)))<=7)
        if !adjustingEdge,m.selection.contains(frame),point.y>=34 {
            exportCandidate=m.selection;anchor=frame;return
        }
        selectionDrag=SelectionDrag(startX:point.x,precise:adjustingEdge)
        if adjustingEdge {
            anchor=abs(frame-m.selection.lowerBound)<abs(frame-m.selection.upperBound) ? m.selection.upperBound : m.selection.lowerBound
        } else { anchor=frame }
        m.select(min(anchor,frame)..<max(anchor,frame));dragX=point.x
        dragTimer?.invalidate()
        dragTimer=Timer.scheduledTimer(withTimeInterval:0.03,repeats:true) {[weak self] _ in self?.autoScroll()}
    }
    override func mouseDragged(with event: NSEvent) {
        guard let m=model,m.canEdit,m.hasAudio else{return}
        if fileDrag {return}
        let point=convert(event.locationInWindow,from:nil),x=point.x;dragX=x
        if let range=exportCandidate {
            if hypot(point.x-exportStart.x,point.y-exportStart.y)>=6 {beginFileDrag(event,range:range,point:point)}
            return
        }
        if overview { m.visibleStart=Double(frameAt(x))-m.visibleLength/2; m.clampView() }
        else if hand { m.visibleStart=originalView-(x-startX)/plotWidth*m.visibleLength; m.clampView() }
        else if selectionDrag.update(x:x) {let f=frameAt(x);m.select(min(f,anchor)..<max(f,anchor))}
    }
    override func scrollWheel(with event: NSEvent) {
        navigateWheel(deltaX:Double(event.scrollingDeltaX),deltaY:Double(event.scrollingDeltaY),
                      precise:event.hasPreciseScrollingDeltas,shift:event.modifierFlags.contains(.shift),
                      pointerX:convert(event.locationInWindow,from:nil).x)
    }
    func navigateWheel(deltaX:Double,deltaY:Double,precise:Bool,shift:Bool,pointerX:Double) {
        guard let m=model,m.canEdit,m.hasAudio,deltaX.isFinite,deltaY.isFinite,pointerX.isFinite else{return}
        if shift || abs(deltaX)>abs(deltaY) {
            let delta=abs(deltaX)>abs(deltaY) ? deltaX : deltaY
            m.pan(delta/plotWidth*m.visibleLength)
        } else if deltaY != 0 {
            // Keep a fractional frame under the pointer, including at sample-level zoom.
            let fraction=max(0,min(1,(pointerX-left)/plotWidth))
            let anchor=overview ? fraction*Double(m.audio.frames) : m.visibleStart+fraction*m.visibleLength
            let exponent=max(-2,min(2,deltaY*(precise ? 0.008 : 0.25)))
            m.zoom(pow(2,exponent),anchor:anchor)
        }
    }
    override func magnify(with event:NSEvent) {model?.zoom(max(0.2,1+event.magnification),anchor:Double(frameAt(convert(event.locationInWindow,from:nil).x)))}
    override func mouseUp(with event:NSEvent) {
        dragTimer?.invalidate();dragTimer=nil;hand=false
        if exportCandidate != nil,!fileDrag {model?.select(anchor..<anchor)}
        exportCandidate=nil
    }
    override func rightMouseDown(with event:NSEvent) {
        guard !overview,let m=model,m.canEdit else{return}
        window?.makeFirstResponder(self);m.playFrom(frameAt(convert(event.locationInWindow,from:nil).x))
    }
    func autoScroll() {
        guard !overview,!hand,selectionDrag.isSelecting,let m=model,m.canEdit else{return}
        let outside=dragX<left ? dragX-left : dragX>bounds.width-12 ? dragX-(bounds.width-12) : 0
        guard outside != 0 else{return}
        m.pan(max(-0.08,min(0.08,outside/plotWidth))*m.visibleLength)
        let f=frameAt(dragX);m.select(min(f,anchor)..<max(f,anchor))
    }
    override func resetCursorRects() {
        guard !overview,let m=model,!m.selection.isEmpty else{return}
        let a=max(left,xAt(m.selection.lowerBound)),b=min(bounds.width-12,xAt(m.selection.upperBound))
        if b>a {addCursorRect(NSRect(x:a,y:34,width:b-a,height:bounds.height-34),cursor:.openHand)}
        for f in [m.selection.lowerBound,m.selection.upperBound] {
            let x=xAt(f);if x>=left && x<=bounds.width-12 {addCursorRect(NSRect(x:x-7,y:34,width:14,height:bounds.height-34),cursor:.resizeLeftRight)}
        }
    }
    func updateGainControl() {
        guard !overview,let m=model else {gainKnob.isHidden=true;return}
        let a=max(left,xAt(m.selection.lowerBound)),b=min(bounds.width-12,xAt(m.selection.upperBound))
        gainKnob.isHidden=m.selection.isEmpty || b<=a
        gainKnob.model=m;gainKnob.frame.origin=NSPoint(x:max(left,min(bounds.width-130,(a+b)/2-59)),y:40)
        gainKnob.refresh()
        m.gainControlContains={ [weak self] point in
            guard let self=self,!self.gainKnob.isHidden else{return false}
            return self.gainKnob.frame.contains(self.convert(point,from:nil))
        }
    }
    override func layout() {super.layout();updateGainControl()}
    private func beginFileDrag(_ event:NSEvent,range:Range<Int>,point:NSPoint) {
        guard let m=model else{return}
        dragTimer?.invalidate();dragTimer=nil;fileDrag=true;exportCandidate=nil
        let token=UUID(),promise=SelectionFilePromise(audio:m.audio,range:range,gain:m.pendingSelectionGain,name:m.name)
        promises[token]=promise;sessionPromise=token;m.activeDragExports += 1
        promise.finished={ [weak self,weak m] error in
            guard self?.promises.removeValue(forKey:token) != nil else{return}
            m?.activeDragExports=max(0,(m?.activeDragExports ?? 1)-1)
            if let error=error {m?.error=error.localizedDescription;m?.status="片段写出失败，原音频未改动"}
            else {m?.status="已拖出 WAV · 48 kHz / 24-bit / 立体声 · 首尾 15 ms 淡化"}
        }
        let provider=NSFilePromiseProvider(fileType:UTType.wav.identifier,delegate:promise)
        let item=NSDraggingItem(pasteboardWriter:provider)
        let image=NSImage(size:NSSize(width:180,height:44),flipped:false) {rect in
            NSColor(calibratedWhite:0.15,alpha:0.95).setFill();NSBezierPath(roundedRect:rect,xRadius:8,yRadius:8).fill()
            ("WAV  48k / 24bit / Stereo" as NSString).draw(at:NSPoint(x:12,y:15),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.systemMint]);return true
        }
        item.setDraggingFrame(NSRect(x:point.x-90,y:point.y-22,width:180,height:44),contents:image)
        m.status="拖到目标文件夹，松开即保存片段"
        beginDraggingSession(with:[item],event:event,source:self)
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {.copy}
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) {
        fileDrag=false
        if operation.isEmpty,let token=sessionPromise,promises.removeValue(forKey:token) != nil {
            model?.activeDragExports=max(0,(model?.activeDragExports ?? 1)-1);model?.status="已取消拖出，原音频未改动"
        }
        sessionPromise=nil
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {
        guard !(sender.draggingSource is WaveformNSView),model?.canEdit == true else{return []}
        return sender.draggingPasteboard.canReadObject(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) ? .copy : []
    }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard !(sender.draggingSource is WaveformNSView),let url=(sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL])?.first else{return false}
        model?.acceptDroppedFile(url);return true
    }
    override func keyDown(with event: NSEvent) { /* Keyboard handling is centralized in AppDelegate. */ }
}
