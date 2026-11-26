import AppKit
import SwiftUI
import AudioCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    var window: NSWindow!
    var model: EditorModel!
    var notesWindow:UsageNotesWindow?
    var allowExit=false
    var keyMonitor: Any?
    var keyboard:EditorKeyboard?
    var pendingURL:URL?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { model=EditorModel(cache:try AudioCache()) } catch { let a=NSAlert(error:error);a.runModal();NSApp.terminate(nil);return }
        NSApp.appearance=NSAppearance(named:.darkAqua)
        window=EditorWindow(contentRect:NSRect(x:0,y:0,width:1280,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        (window as? EditorWindow)?.editor=model
        window.title="声刻 · Wave Studio"; window.titlebarAppearsTransparent=true; window.backgroundColor=NSColor(calibratedRed:0.105,green:0.123,blue:0.145,alpha:1)
        window.minSize=NSSize(width:1080,height:728); window.delegate=self; window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:ContentView(model:model)); window.center(); window.makeKeyAndOrderFront(nil)
        do {
            let base=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("WaveStudio")
            notesWindow=UsageNotesWindow(store:try UsageNotesStore(url:base.appendingPathComponent("使用建议.md"),version:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.4.0"))
        } catch {model.error="使用建议无法初始化：\(error.localizedDescription)"}
        model.usageNotesView=notesWindow?.view
        notesWindow?.onPresent={ [weak self] in self?.model.showingUsageNotes=true }
        notesWindow?.onClose={ [weak self] in self?.model.showingUsageNotes=false;self?.model.focusWaveform?() }
        model.showUsageNotes={ [weak self] in
            guard let self=self else{return}
            if self.model.showingUsageNotes {if self.notesWindow?.save()==true {self.model.showingUsageNotes=false;self.model.focusWaveform?()}}
            else {self.notesWindow?.present()}
        }
        model.importUsageNotes={ [weak self] url in self?.notesWindow?.importFile(url) }
        buildMenu(); NSApp.activate(ignoringOtherApps:true)
        keyboard=EditorKeyboard(model:model) { [weak self] event in
            guard let self=self else{return false}
            return event.window===self.window && self.window.attachedSheet==nil && !(self.window.firstResponder is NSTextView) && !self.model.busy
        }
        keyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown,handler:keyboard!.monitor)
        if let url=pendingURL {model.openURL(url);pendingURL=nil}
        if CommandLine.arguments.contains("--demo") { model.demo() }
        if let index=CommandLine.arguments.firstIndex(of:"--open"),CommandLine.arguments.count>index+1 { model.openURL(URL(fileURLWithPath:CommandLine.arguments[index+1])) }
    }
    func application(_ sender:NSApplication,open urls:[URL]) { if let url=urls.first { if model == nil {pendingURL=url} else {model.openURL(url)} } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func windowShouldClose(_ sender:NSWindow)->Bool {
        if model.flushSelectionGain({self.window.performClose(nil)}) {return false}
        if model.activeDragExports>0 {model.error="请等待拖出的片段写入完成。";return false}
        if notesWindow?.save()==false {model.error="使用建议未能保存，请检查建议窗口中的原因。";return false}
        if model.panelPresented {return false}
        if model.busy || model.recording { model.error="请先停止录音或等待当前操作结束。";return false }
        if model.dirty { model.confirmDiscard {self.allowExit=true;NSApp.terminate(nil)};return false };return true
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if allowExit || model == nil {return .terminateNow}
        if model.flushSelectionGain({NSApp.terminate(nil)}) {return .terminateCancel}
        if model.activeDragExports>0 {model.error="请等待拖出的片段写入完成。";return .terminateCancel}
        if notesWindow?.save()==false {model.error="使用建议未能保存，请检查建议窗口中的原因。";return .terminateCancel}
        if model.panelPresented {return .terminateCancel}
        if model.busy || model.recording {model.error="请先停止录音或等待当前操作结束。";return .terminateCancel}
        if model.dirty {model.confirmDiscard {self.allowExit=true;NSApp.terminate(nil)};return .terminateCancel}
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { model?.stop(); if let folder=model?.cache.folder { try? FileManager.default.removeItem(at:folder) } }
    func item(_ title:String,_ key:String="",_ tag:Int=0,modifiers:NSEvent.ModifierFlags = .command)->NSMenuItem {
        let i=NSMenuItem(title:title,action:#selector(command(_:)),keyEquivalent:key);i.target=self;i.tag=tag;i.keyEquivalentModifierMask=modifiers
        let native:[Int:Selector]=[20:#selector(EditorWindow.undo(_:)),21:#selector(EditorWindow.redo(_:)),22:#selector(EditorWindow.cut(_:)),23:#selector(EditorWindow.copy(_:)),24:#selector(EditorWindow.paste(_:)),25:#selector(EditorWindow.selectAll(_:))]
        if let action=native[tag] {i.action=action;i.target=nil}
        return i
    }
    func buildMenu() {
        let bar=NSMenu()
        func submenu(_ title:String)->NSMenu {let i=NSMenuItem();i.title=title;let m=NSMenu(title:title);i.submenu=m;bar.addItem(i);return m}
        let app=submenu("声刻")
        app.addItem(item("关于声刻","",1));app.addItem(.separator());app.addItem(NSMenuItem(title:"隐藏声刻",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h"));app.addItem(.separator());app.addItem(NSMenuItem(title:"退出声刻",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"))
        let file=submenu("文件");file.addItem(item("打开音频…","o",12))
        let recent=NSMenuItem(title:"打开最近使用",action:nil,keyEquivalent:"");let recentMenu=NSMenu(title:"打开最近使用");recentMenu.delegate=self;recent.submenu=recentMenu;file.addItem(recent)
        file.addItem(.separator());file.addItem(item("写入并覆盖原文件","s",15));file.addItem(item("保存为副本…","s",16,modifiers:[.command,.shift]));file.addItem(item("删除源文件并保存为 WAV","",14));file.addItem(.separator());file.addItem(NSMenuItem(title:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w"))
        let edit=submenu("编辑");edit.addItem(item("撤销","z",20));edit.addItem(item("重做","z",21,modifiers:[.command,.shift]));edit.addItem(.separator());edit.addItem(item("剪切","x",22));edit.addItem(item("复制","c",23));edit.addItem(item("粘贴","v",24));edit.addItem(item("全选","a",25));edit.addItem(item("删除选区","",26));edit.addItem(item("裁剪至选区","t",27));edit.addItem(item("插入静音…","",28))
        let audio=submenu("音频");audio.addItem(item("播放 / 停止","",30));audio.addItem(item("暂停 / 继续","",35));audio.addItem(item("停止","",31));audio.addItem(item("停止并定位到播放头","",36));audio.addItem(item("开始 / 结束录音","",32));audio.addItem(item("循环播放","l",33));audio.addItem(item("添加标记","",34))
        let effects=submenu("效果");effects.addItem(item("淡入","",40));effects.addItem(item("淡出","",41));effects.addItem(item("峰值归一化…","",42));effects.addItem(item("静音","",43));effects.addItem(item("倒放","",44));effects.addItem(item("反相","",45))
        let view=submenu("显示");view.addItem(item("放大","+",50));view.addItem(item("缩小","-",51));view.addItem(item("显示全曲","0",52));view.addItem(item("缩放至选区","",53));view.addItem(item("恢复上次视图","",54));view.addItem(.separator());view.addItem(item("最大化 / 还原窗口","",55))
        let help=submenu("帮助");help.addItem(item("使用说明","",60));NSApp.mainMenu=bar
    }
    @objc func command(_ sender:NSMenuItem) {
        if let text=NSApp.keyWindow?.firstResponder as? NSTextView {
            switch sender.tag {case 20:text.undoManager?.undo();return;case 21:text.undoManager?.redo();return;case 22:text.cut(nil);return;case 23:text.copy(nil);return;case 24:text.paste(nil);return;case 25:text.selectAll(nil);return;default:break}
        }
        switch sender.tag {
        case 1: NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"声刻 · Wave Studio",.applicationVersion:"0.4.0 开发预览",.credits:NSAttributedString(string:"Swift 原生音频编辑器\n参考 Sound Studio 操作流程，独立实现。")])
        case 10:model.newDocument(channels:2)
        case 11:model.newDocument(channels:1)
        case 12:model.openPanel()
        case 13:model.demo()
        case 14:model.convertSourceToWAV()
        case 15:model.overwriteOriginal()
        case 16:model.saveCopy()
        case 90:if let url=sender.representedObject as? URL {model.openURL(url)}
        case 20:model.undo()
        case 21:model.redo()
        case 22:model.cut()
        case 23:model.copy()
        case 24:model.paste()
        case 25:model.select(0..<model.audio.frames)
        case 26:model.deleteSelection()
        case 27:model.crop()
        case 28:model.showSilence=true
        case 30:model.togglePlay()
        case 31:model.stop()
        case 32:model.record()
        case 33:model.toggleLoop()
        case 34:model.addMarker()
        case 35:model.pauseResume()
        case 36:model.stopAtPlayhead()
        case 40:model.fade(inward:true)
        case 41:model.fade(inward:false)
        case 42:model.showNormalize=true
        case 43:model.effect(.silence,name:"静音")
        case 44:model.effect(.reverse,name:"倒放")
        case 45:model.effect(.invert,name:"反相")
        case 50:model.zoom(2)
        case 51:model.zoom(0.5)
        case 52:model.fit()
        case 53:model.zoomSelection()
        case 54:model.restoreView()
        case 55:(window as? EditorWindow)?.toggleMaximize(nil)
        case 60:let a=NSAlert();a.messageText="声刻快捷操作";a.informativeText="空格：播放选区 / 停止；Shift + 空格：从光标播放到末尾。\n逗号或 P：暂停 / 继续；X：停止并定位。\n双击顶部标题栏或文件栏空白处：最大化 / 还原窗口。\n拖动波形选区，拖边界精调，右键从此试听。\n滚轮以指针位置横向缩放；Shift + 滚轮平移。\n选区上方旋钮滚轮调音量，点击别处完成并平滑衔接。\n按住选区内部拖出：48kHz/24-bit/立体声 WAV，首尾 15ms 淡化。\n右上角感叹号记录建议，关闭即保存，升级保留全文。\nShift + 方向键伸缩选区，⌥← / ⌥→ 跳到标记。\nR / T 缩小放大；Q / W 显示选区起终点；E 恢复视图。\nM 添加标记；D / G 对选区淡入淡出；4 切换循环。\n⌘S 原编码覆盖；⇧⌘S 原编码副本；第三按钮转为 WAV。\n\n峰值表在监听音量之前。点击峰值数字重置保持与削波灯。\n从 Finder 的“打开方式”打开音频，或拖入窗口 / Dock 图标。\n三个保存动作都保存完整文件。临时标记和撤销只在本次编辑有效。";a.runModal()
        default:break
        }
    }
    func validateMenuItem(_ menuItem:NSMenuItem)->Bool {
        guard model != nil else{return false}
        if NSApp.keyWindow?.firstResponder is NSTextView && (20...25).contains(menuItem.tag) {return true}
        switch menuItem.tag {
        case 1,55,60:return true
        case 31:return !model.busy
        case 32:return !model.busy
        case 20:return model.canEdit && model.undoName != nil
        case 21:return model.canEdit && model.redoName != nil
        case 35:return model.canEdit && (model.playing || model.paused)
        case 22,23,26,27,40,41,53:return model.canEdit && !model.selection.isEmpty
        case 24:return model.canPaste
        case 14,15:return model.canEdit && model.hasAudio && model.sourceFile != nil
        case 16,25,30,33,34,36,42...52,54:return model.canEdit && model.hasAudio
        default:return model.canEdit
        }
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs.filter({$0.pathExtension.lowercased() != "waveproj"}).prefix(12) {let entry=item(url.lastPathComponent,"",90);entry.representedObject=url;entry.toolTip=url.path;menu.addItem(entry)}
        if menu.items.isEmpty {let empty=NSMenuItem(title:"尚无最近使用文件",action:nil,keyEquivalent:"");empty.isEnabled=false;menu.addItem(empty)}
    }

}
let app=NSApplication.shared
let delegate=AppDelegate()
app.setActivationPolicy(.regular)
app.delegate=delegate
app.run()
