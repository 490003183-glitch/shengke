import AppKit

// Native selectors let text editors and the system file panels receive editing
// commands first. Audio operations are the window's responder-chain fallback.
final class EditorWindow:NSWindow {
    weak var editor:EditorModel?
    private var zoomState=WindowZoomState()
    @objc func toggleMaximize(_ sender:Any?) {
        guard attachedSheet==nil,!styleMask.contains(.fullScreen),let screen=screen else{return}
        setFrame(zoomState.nextFrame(current:frame,visible:screen.visibleFrame),display:true,animate:true)
    }
    override func zoom(_ sender:Any?) {toggleMaximize(sender)}
    override func sendEvent(_ event:NSEvent) {
        let location=event.locationInWindow
        let titlebar=location.y>=contentLayoutRect.maxY
        // The file header is 74pt high. Leave all three action buttons to their controls.
        let fileHeader=location.y>=contentLayoutRect.maxY-74 && location.y<contentLayoutRect.maxY && location.x<frame.width-580
        if event.type == .leftMouseDown,event.clickCount==2,(titlebar || fileHeader) {
            let buttons:[NSWindow.ButtonType]=[.closeButton,.miniaturizeButton,.zoomButton]
            let onButton=buttons.contains {type in
                guard let button=standardWindowButton(type) else{return false}
                return button.convert(button.bounds,to:nil).insetBy(dx:-4,dy:-4).contains(event.locationInWindow)
            }
            if !onButton {toggleMaximize(nil);return}
        }
        let finishGain=event.type == .leftMouseUp && !(editor?.gainControlContains?(location) ?? false)
        super.sendEvent(event)
        if finishGain {editor?.flushSelectionGain()}
    }
    @objc func undo(_ sender:Any?) {editor?.undo()}
    @objc func redo(_ sender:Any?) {editor?.redo()}
    @objc func cut(_ sender:Any?) {editor?.cut()}
    @objc func copy(_ sender:Any?) {editor?.copy()}
    @objc func paste(_ sender:Any?) {editor?.paste()}
    override func selectAll(_ sender:Any?) {
        guard let m=editor else{return};m.select(0..<m.audio.frames);m.focusWaveform?()
    }
    override func validateUserInterfaceItem(_ item:NSValidatedUserInterfaceItem)->Bool {
        guard let m=editor else{return false}
        switch item.action {
        case #selector(undo(_:)):return m.canEdit && m.undoName != nil
        case #selector(redo(_:)):return m.canEdit && m.redoName != nil
        case #selector(cut(_:)),#selector(copy(_:)):return m.canEdit && !m.selection.isEmpty
        case #selector(paste(_:)):return m.canPaste
        case #selector(selectAll(_:)):return m.canEdit && m.hasAudio
        default:return super.validateUserInterfaceItem(item)
        }
    }
}

struct WindowZoomState {
    private var restoreFrame:NSRect?
    mutating func nextFrame(current:NSRect,visible:NSRect)->NSRect {
        let maximized=abs(current.minX-visible.minX)<1 && abs(current.minY-visible.minY)<1 && abs(current.width-visible.width)<1 && abs(current.height-visible.height)<1
        if maximized,let restore=restoreFrame {restoreFrame=nil;return restore}
        restoreFrame=current;return visible
    }
}
