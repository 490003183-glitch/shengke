import AppKit

final class EditorKeyboard {
    weak var model:EditorModel?
    let shouldHandle:(NSEvent)->Bool
    init(model:EditorModel,shouldHandle:@escaping(NSEvent)->Bool) {self.model=model;self.shouldHandle=shouldHandle}
    var monitor:(NSEvent)->NSEvent? {
        { [weak self] event in
            guard let self=self else{return event}
            // nil means consumed. Never coalesce a handled nil back into the event.
            return self.handle(event)
        }
    }
    func handle(_ e:NSEvent)->NSEvent? {
        guard let model=model,shouldHandle(e) else{return e}
        if e.modifierFlags.intersection([.command,.control,.option]) == .option && (e.keyCode==123 || e.keyCode==124) {model.goToMarker(next:e.keyCode==124);return nil}
        if !e.modifierFlags.intersection([.command,.control,.option]).isEmpty {return e}
        let character=e.charactersIgnoringModifiers?.lowercased() ?? ""
        let handledCodes:Set<UInt16>=[53,49,43,36,51,117,115,119,123,124]
        let handledLetters:Set<String>=["m",",","p","x","d","g","r","t","q","w","e","3","4","=","+","-"]
        let repeats=[UInt16(123),124,51,117].contains(e.keyCode) || ["r","t","=","+","-"].contains(character)
        if e.isARepeat && !repeats && (handledCodes.contains(e.keyCode) || handledLetters.contains(character)) {return nil}
        switch e.keyCode {
        case 53:model.stop();return nil
        case 49:model.togglePlay(ignoreSelection:e.modifierFlags.contains(.shift));return nil
        case 43:model.pauseResume();return nil
        case 36:if model.canEdit {model.stop();model.select(0..<0)};return nil
        case 51,117:model.deleteSelection();return nil
        case 115:if model.canEdit {model.select(0..<0);model.centerSelection(end:false)};return nil
        case 119:if model.canEdit {model.select(model.audio.frames..<model.audio.frames);model.centerSelection(end:true)};return nil
        case 123,124:model.moveCursor(direction:e.keyCode==123 ? -1 : 1,extend:e.modifierFlags.contains(.shift));return nil
        default:break
        }
        switch character {
        case "m":model.addMarker();return nil
        case ",","p":model.pauseResume();return nil
        case "x":model.stopAtPlayhead();return nil
        case "d":model.fade(inward:true);return nil
        case "g":model.fade(inward:false);return nil
        case "r":model.zoom(0.5);return nil
        case "t":model.zoom(2);return nil
        case "q":model.centerSelection(end:false);return nil
        case "w":model.centerSelection(end:true);return nil
        case "e":model.restoreView();return nil
        case "3":model.record();return nil
        case "=","+":model.zoom(2);return nil
        case "-":model.zoom(0.5);return nil
        case "4":if model.canEdit {model.toggleLoop()};return nil
        default:return e
        }
    }
}
