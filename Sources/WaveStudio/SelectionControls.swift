import AppKit
import AudioCore
import UniformTypeIdentifiers

final class SelectionGainKnob:NSView {
    weak var model:EditorModel?
    private var previousY:CGFloat=0
    override var isFlipped:Bool {true}
    override init(frame:NSRect) {
        super.init(frame:frame);setAccessibilityRole(.slider);setAccessibilityLabel("选区音量")
        toolTip="滚轮上下调节选区音量 · 拖动旋钮也可调节 · 点击别处完成，自动平滑衔接"
    }
    required init?(coder:NSCoder) {fatalError()}
    func refresh() {setAccessibilityValue(String(format:"%+.1f dB",model?.selectionGainDB ?? 0));needsDisplay=true}
    override func draw(_ dirtyRect:NSRect) {
        let db=model?.selectionGainDB ?? 0
        NSColor(calibratedWhite:0.12,alpha:0.97).setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:16,yRadius:16).fill()
        NSColor.systemMint.withAlphaComponent(0.7).setStroke();NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:16,yRadius:16).stroke()
        let center=NSPoint(x:22,y:20),angle=(-90+max(-135,min(135,db/24*135)))*Double.pi/180
        NSColor.white.withAlphaComponent(0.2).setStroke();let circle=NSBezierPath(ovalIn:NSRect(x:10,y:8,width:24,height:24));circle.lineWidth=2;circle.stroke()
        NSColor.systemMint.setStroke();let hand=NSBezierPath();hand.lineWidth=2;hand.move(to:center);hand.line(to:NSPoint(x:center.x+cos(angle)*9,y:center.y+sin(angle)*9));hand.stroke()
        (String(format:"%+.1f dB",db) as NSString).draw(at:NSPoint(x:42,y:12),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:12,weight:.medium),.foregroundColor:NSColor.white])
    }
    override func mouseDown(with event:NSEvent) {previousY=event.locationInWindow.y;window?.makeFirstResponder(superview)}
    override func mouseDragged(with event:NSEvent) {let dy=event.locationInWindow.y-previousY;previousY=event.locationInWindow.y;model?.adjustSelectionGain(by:Double(dy)*0.15)}
    override func otherMouseDown(with event:NSEvent) {mouseDown(with:event)}
    override func otherMouseDragged(with event:NSEvent) {mouseDragged(with:event)}
    override func scrollWheel(with event:NSEvent) {
        guard event.momentumPhase.isEmpty,event.scrollingDeltaY != 0 else{return}
        let fine=event.modifierFlags.contains(.shift)
        let delta=event.hasPreciseScrollingDeltas ? Double(event.scrollingDeltaY)*(fine ? 0.01 : 0.05) : (event.scrollingDeltaY>0 ? 1.0 : -1.0)*(fine ? 0.1 : 0.5)
        model?.adjustSelectionGain(by:delta)
    }
    override func accessibilityPerformIncrement()->Bool {model?.adjustSelectionGain(by:0.5);return true}
    override func accessibilityPerformDecrement()->Bool {model?.adjustSelectionGain(by:-0.5);return true}
}

final class SelectionFilePromise:NSObject,NSFilePromiseProviderDelegate {
    let audio:AudioDocument,range:Range<Int>,gain:SelectionGain?,name:String
    let queue=OperationQueue()
    var finished:((Error?)->Void)?
    init(audio:AudioDocument,range:Range<Int>,gain:SelectionGain?,name:String) {
        self.audio=audio;self.range=range;self.gain=gain
        let base=(name as NSString).deletingPathExtension.replacingOccurrences(of:"/",with:"-").replacingOccurrences(of:":",with:"-")
        self.name="\(base)-片段-\(Int(Double(range.lowerBound)/audio.rate*1000))-\(Int(Double(range.upperBound)/audio.rate*1000))ms.wav"
        super.init();queue.qualityOfService = .userInitiated;queue.maxConcurrentOperationCount=1
    }
    func filePromiseProvider(_ filePromiseProvider:NSFilePromiseProvider,fileNameForType fileType:String)->String {name}
    func operationQueue(for filePromiseProvider:NSFilePromiseProvider)->OperationQueue {queue}
    func filePromiseProvider(_ filePromiseProvider:NSFilePromiseProvider,writePromiseTo url:URL,completionHandler:@escaping(Error?)->Void) {
        var coordinationError:NSError?,writeError:Error?
        NSFileCoordinator().coordinate(writingItemAt:url,options:[],error:&coordinationError) {destination in
            do {try ClipExporter.write(audio,range:range,gain:gain,to:destination)} catch {writeError=error}
        }
        let error=writeError ?? coordinationError
        completionHandler(error)
        DispatchQueue.main.async {self.finished?(error)}
    }
}
