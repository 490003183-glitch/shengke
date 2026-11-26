import SwiftUI
import AppKit
import AudioCore

private let panelColor=Color(red:0.105,green:0.123,blue:0.145)
private let mint=Color(red:0.40,green:0.87,blue:0.74)
struct Tool: View {
    let title:String
    let icon:String
    var enabled=true
    var hint=""
    var action:()->Void
    var body:some View {
        Button(action:action) {VStack(spacing:5) {Image(systemName:icon).font(.system(size:15));Text(title).font(.system(size:11))}.frame(minWidth:40,minHeight:43)}
            .buttonStyle(.plain).foregroundStyle(enabled ? Color.white.opacity(0.85) : Color.white.opacity(0.22)).disabled(!enabled).help(hint.isEmpty ? title : hint).accessibilityLabel(title)
    }
}
struct ContentView: View {
    @ObservedObject var model:EditorModel
    var canSelect:Bool {model.canEdit && !model.selection.isEmpty}
    var canProcess:Bool {model.canEdit && model.hasAudio}
    var body:some View {
        VStack(spacing:0) {
            header
            Divider().opacity(0.4)
            tools
            Divider().opacity(0.4)
            HStack(spacing:0) {
                VStack(spacing:0) {
                    if model.hasAudio {
                        HStack {Text("全局总览");Spacer();Text("滚轮随指针缩放 · 旋钮调音量 · 选区拖出 WAV")}.font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,18).padding(.top,12).padding(.bottom,7)
                        WaveformSurface(model:model,overview:true).frame(height:54).clipShape(RoundedRectangle(cornerRadius:6)).padding(.horizontal,16).padding(.bottom,12)
                        Divider().opacity(0.25)
                        WaveformSurface(model:model).frame(maxWidth:.infinity,maxHeight:.infinity)
                        zoomBar
                    } else {welcome.frame(maxWidth:.infinity,maxHeight:.infinity)}
                }
                Divider().opacity(0.5)
                inspector.frame(width:280)
            }
            Divider().opacity(0.4)
            transport
            Divider().opacity(0.25)
            HStack(spacing:8) {
                Circle().fill(model.recording ? Color.red : mint.opacity(0.7)).frame(width:5,height:5)
                Text(model.status).lineLimit(1)
                Spacer()
                Text("\(model.audio.rate/1000,specifier:"%.1f") kHz · \(model.audio.channels == 2 ? "立体声" : "单声道")").foregroundStyle(.secondary)
            }.font(.system(size:11)).padding(.horizontal,18).frame(height:30).background(Color.black.opacity(0.13))
        }
        .background(Color(red:0.075,green:0.09,blue:0.11)).foregroundStyle(Color.white.opacity(0.9)).preferredColorScheme(.dark)
        .frame(minWidth:1080,minHeight:700)
        .overlay {if model.busy {ZStack {Color.black.opacity(0.32);VStack(spacing:14) {ProgressView().controlSize(.large);Text(model.status).font(.system(size:13))}.padding(30).background(panelColor,in:RoundedRectangle(cornerRadius:14))}.allowsHitTesting(true)}}
        .overlay(alignment:.topTrailing) {
            if model.showingUsageNotes,let view=model.usageNotesView {
                UsageNotesSurface(view:view).frame(width:610,height:450).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(Color.white.opacity(0.18))).shadow(color:.black.opacity(0.5),radius:24).padding(.top,82).padding(.trailing,18)
            }
        }
        .alert("操作未完成",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) {Button("好"){model.error=nil}} message:{Text(model.error ?? "")}
        .sheet(isPresented:$model.showNormalize) {normalizeSheet}
        .sheet(isPresented:$model.showSilence) {silenceSheet}
        .onChange(of:model.timeUnit) {_,_ in model.syncSelectionText()}
        .onDrop(of:["public.file-url"],isTargeted:nil) {providers in
            guard model.canEdit,let p=providers.first else{return false}
            _=p.loadObject(ofClass:URL.self) {url,_ in if let url=url {DispatchQueue.main.async {model.acceptDroppedFile(url)}}};return true
        }
    }
    var header:some View {
        HStack(spacing:12) {
            HStack(spacing:12) {
            Image(systemName:"waveform").font(.system(size:24,weight:.medium)).foregroundStyle(mint).frame(width:40,height:40).background(mint.opacity(0.12),in:RoundedRectangle(cornerRadius:10))
            VStack(alignment:.leading,spacing:3) {Text("声刻").font(.system(size:17,weight:.semibold));Text("WAVE STUDIO").font(.system(size:8,weight:.medium)).tracking(2).foregroundStyle(.secondary)}
            Rectangle().fill(Color.white.opacity(0.1)).frame(width:1,height:28).padding(.horizontal,9)
            VStack(alignment:.leading,spacing:4) {
                HStack(spacing:6) {Text(model.name).font(.system(size:13,weight:.medium)).lineLimit(1);if model.dirty {Circle().fill(.orange).frame(width:6,height:6).help("有未保存的音频修改")}}
                Text(model.hasAudio ? "\(time(model.audio.duration)) · \(model.sourceEncoding.description)" : "从文件打开，处理后直接保存").font(.system(size:11)).foregroundStyle(.secondary)
            }
            Spacer(minLength:8)
            }.contentShape(Rectangle()).help("双击空白处最大化 / 还原窗口")
            Button {model.overwriteOriginal()} label:{Label("写入并覆盖原文件",systemImage:"checkmark.circle")}.disabled(!canProcess || model.sourceFile == nil).help("⌘S · 保留源文件编码，保存完整音频")
            Button {model.saveCopy()} label:{Label("保存为副本",systemImage:"doc.on.doc")}.disabled(!canProcess).help("⇧⌘S · 选择音频格式，原文件不变")
            Button {model.convertSourceToWAV()} label:{Label("删除源文件并保存为 WAV",systemImage:"arrow.triangle.2.circlepath")}.disabled(!canProcess || model.sourceFile == nil).help("在原目录保存完整 WAV 24-bit，校验成功后将源文件移入废纸篓")
            Button {model.showUsageNotes?()} label:{Image(systemName:"exclamationmark.circle").font(.system(size:18))}.buttonStyle(.plain).help("使用建议 · 关闭即保存").accessibilityLabel("使用建议")

        }.font(.system(size:12)).padding(.horizontal,20).frame(height:74).background(panelColor)
    }
    var tools:some View {
        HStack(spacing:7) {
            Tool(title:"撤销",icon:"arrow.uturn.backward",enabled:model.canEdit && model.undoName != nil,hint:model.undoName.map{"撤销\($0) · ⌘Z"} ?? "撤销"){model.undo()}
            Tool(title:"重做",icon:"arrow.uturn.forward",enabled:model.canEdit && model.redoName != nil){model.redo()}
            toolDivider
            Tool(title:"剪切",icon:"scissors",enabled:canSelect,hint:"剪切选区 · ⌘X"){model.cut()}
            Tool(title:"复制",icon:"doc.on.doc",enabled:canSelect,hint:"复制选区 · ⌘C"){model.copy()}
            Tool(title:"粘贴",icon:"doc.on.clipboard",enabled:model.canPaste,hint:"在光标处插入，或替换选区 · ⌘V"){model.paste()}
            Tool(title:"删除",icon:"delete.left",enabled:canSelect){model.deleteSelection()}
            Tool(title:"裁剪",icon:"crop",enabled:canSelect,hint:"只保留选区 · ⌘T"){model.crop()}
            toolDivider
            Tool(title:"淡入",icon:"chart.line.uptrend.xyaxis",enabled:canSelect,hint:"对当前选区淡入 · D"){model.fade(inward:true)}
            Tool(title:"淡出",icon:"chart.line.downtrend.xyaxis",enabled:canSelect,hint:"对当前选区淡出 · G"){model.fade(inward:false)}
            Tool(title:"归一化",icon:"waveform.path",enabled:canProcess,hint:"设置峰值目标并预听"){model.showNormalize=true}
            Spacer()
            Text("空格 播放/停止 · , 暂停").font(.system(size:11)).foregroundStyle(.secondary).padding(.trailing,8)
        }.padding(.horizontal,14).frame(height:62).background(panelColor.opacity(0.65))
    }
    var toolDivider:some View {Rectangle().fill(Color.white.opacity(0.1)).frame(width:1,height:26).padding(.horizontal,6)}
    var welcome:some View {
        VStack(spacing:20) {
            Image(systemName:"waveform.path").font(.system(size:64,weight:.ultraLight)).foregroundStyle(mint.opacity(0.8)).padding(.bottom,8)
            Text("直接从音频文件开始").font(.system(size:23,weight:.medium))
            Text("在 Finder 右键音频 → 打开方式 → 声刻，或把文件拖到这里").font(.system(size:13)).foregroundStyle(.secondary)
            HStack(spacing:22) {Label("原编码覆盖",systemImage:"checkmark.circle");Label("副本可选格式",systemImage:"doc.on.doc");Label("转为 WAV",systemImage:"waveform")}.font(.system(size:12)).foregroundStyle(.secondary).padding(.top,20)
        }
    }
    var zoomBar:some View {
        HStack(spacing:14) {
            Button {model.zoom(0.5)} label:{Image(systemName:"minus.magnifyingglass")}.help("缩小 · R")
            Button {model.zoom(2)} label:{Image(systemName:"plus.magnifyingglass")}.help("围绕光标放大 · T")
            Button("全曲"){model.fit()}.help("⌘0")
            Button("选区"){model.zoomSelection()}.disabled(model.selection.isEmpty)
            Spacer()
            Toggle("跟随播放",isOn:$model.followPlayback).toggleStyle(.checkbox)
            Menu {ForEach([1.0,2,4,8,16],id:\.self) {scale in Button("\(Int(scale))×"){model.verticalScale=scale}}} label:{Text("振幅 \(Int(model.verticalScale))×")}.frame(width:88).help("仅改变显示，不改变音量")
        }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,18).frame(height:40).background(panelColor.opacity(0.5))
    }
    var inspector:some View {
        VStack(spacing:0) {
            Picker("编辑面板",selection:$model.inspectorTab) {Text("选区与处理").tag(0);Text("标记 · \(model.audio.markers.count)").tag(1)}.pickerStyle(.segmented).labelsHidden().padding(14)
            ScrollView {
                VStack(alignment:.leading,spacing:17) {
                    if model.inspectorTab==0 {selectionPanel;Divider().opacity(0.4);effectsPanel}
                    else {markersPanel}
                }.padding(.horizontal,18).padding(.bottom,18)
            }
        }.background(panelColor)
        .alert("标记改名",isPresented:Binding(get:{model.renameID != nil},set:{if !$0 {model.renameID=nil}})) {
            TextField("标记名称",text:$model.markerName)
            Button("取消",role:.cancel){model.renameID=nil}
            Button("保存"){if let m=model.audio.markers.first(where:{$0.id==model.renameID}) {model.renameMarker(m,name:model.markerName.isEmpty ? "标记" : model.markerName)};model.renameID=nil;model.focusWaveform?()}
        }
    }
    var selectionPanel:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {section("时间选区",icon:"selection.pin.in.out");Spacer();Text("全部声道").font(.system(size:10)).foregroundStyle(.secondary)}
            Picker("时间单位",selection:$model.timeUnit) {ForEach(TimeUnit.allCases,id:\.self) {Text($0.rawValue).tag($0)}}.pickerStyle(.segmented).labelsHidden()
            timeField("起点",text:$model.startText)
            timeField("终点",text:$model.endText)
            timeField("长度",text:$model.lengthText,useLength:true)
            HStack {Button("全选"){model.select(0..<model.audio.frames);model.focusWaveform?()};Button("清除选区"){model.select(model.selection.lowerBound..<model.selection.lowerBound);model.focusWaveform?()}.disabled(model.selection.isEmpty);Spacer();Button("设置起止"){model.applySelection()}}.disabled(!canProcess)
            Text(model.timeUnit == .samples ? "单位：样本帧 · 终点不包含在选区内" : "时:分:秒，可直接输入秒数 · 回车确认").font(.system(size:10)).foregroundStyle(.secondary)
        }
    }
    var effectsPanel:some View {
        VStack(alignment:.leading,spacing:11) {
            section("音量与处理",icon:"slider.horizontal.3")
            scopeLabel
            Text("选中片段后，在波形上方的小旋钮滚动鼠标滚轮调音量；点别处即完成，边界自动平滑衔接。").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4)
            Text("拖出选区：WAV · 48 kHz · 24-bit · 立体声\n首尾自动加 15 ms 淡入淡出").font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4)
            HStack {Button("静音"){model.effect(.silence,name:"静音")};Button("倒放"){model.effect(.reverse,name:"倒放")};Button("反相"){model.effect(.invert,name:"反相")}}.disabled(!canProcess)
            Text("音量修改可撤销 · Shift + 滚轮精调\n淡入 / 淡出需先选择范围。").font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
    var scopeDuration:String {
        let count=model.effectiveRange.count
        return count>0 && Double(count)/model.audio.rate<0.001 ? "\(count) 样本帧" : time(Double(count)/model.audio.rate)
    }
    var scopeLabel:some View {
        HStack(spacing:6) {Image(systemName:model.selection.isEmpty ? "waveform" : "selection.pin.in.out");Text("\(model.selection.isEmpty ? "处理整段" : "处理选区") · \(scopeDuration)").monospacedDigit()}
            .font(.system(size:11,weight:.medium)).foregroundStyle(model.selection.isEmpty ? Color.orange : mint).padding(8).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:5))
    }
    var markersPanel:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {section("标记列表",icon:"bookmark");Spacer();Button("添加 · M"){model.addMarker()}.disabled(!canProcess)}
            Text("播放时按 M 标记当前位置。\n⌥← / ⌥→ 跳到前后标记。").font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4)
            ForEach(model.audio.markers) {marker in
                HStack(spacing:7) {
                    Image(systemName:"bookmark.fill").font(.system(size:11)).foregroundStyle(.orange)
                    Button {model.select(marker.frame..<marker.frame);model.centerSelection(end:false);model.focusWaveform?()} label:{VStack(alignment:.leading,spacing:4) {Text(marker.name).font(.system(size:12)).lineLimit(1);Text(time(Double(marker.frame)/model.audio.rate)).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)}}.buttonStyle(.plain)
                    Spacer()
                    Menu {Button("改名…"){model.renameID=marker.id;model.markerName=marker.name};Button("删除",role:.destructive){model.deleteMarker(marker)}} label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).frame(width:20)
                }.padding(9).background(Color.white.opacity(0.035),in:RoundedRectangle(cornerRadius:5)).disabled(!model.canEdit)
            }
            Text("临时定位标记，仅在本次编辑中使用。").font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
    func section(_ title:String,icon:String)->some View {Label(title,systemImage:icon).font(.system(size:12,weight:.medium)).foregroundStyle(Color.white.opacity(0.75))}
    func timeField(_ title:String,text:Binding<String>,useLength:Bool=false)->some View {
        HStack {Text(title).font(.system(size:12)).foregroundStyle(.secondary);Spacer();TextField(title,text:text).font(.system(size:12,design:.monospaced)).multilineTextAlignment(.trailing).frame(width:184).onSubmit{model.applySelection(useLength:useLength)}.accessibilityLabel("选区"+title)}
    }
    var playbackScope:String {
        if model.selection.isEmpty {return "从光标到末尾"}
        let seconds=Double(model.selection.count)/model.audio.rate
        return seconds<1 ? "选区 \(String(format:"%.2f",seconds*1000)) ms" : "选区 \(String(format:"%.2f",seconds)) 秒"
    }
    var transport:some View {
        HStack(spacing:18) {
            HStack(spacing:17) {
                Button {model.stop();model.select(0..<0);model.focusWaveform?()} label:{Image(systemName:"backward.end.fill")}.help("回到开头 · Return").accessibilityLabel("回到开头")
                Button {model.togglePlay()} label:{Image(systemName:(model.playing || model.paused) ? "stop.fill" : "play.fill").font(.system(size:17)).frame(width:44,height:36).background(mint,in:RoundedRectangle(cornerRadius:9)).foregroundStyle(.black)}.disabled(!canProcess).help("空格试听选区；⇧空格从光标播放到末尾").accessibilityLabel(model.playing || model.paused ? "停止播放" : "播放")
                Button {model.pauseResume()} label:{Image(systemName:"pause.fill").foregroundStyle(model.paused ? mint : Color.primary)}.disabled(!model.playing && !model.paused).help("暂停 / 继续 · 逗号或 P").accessibilityLabel(model.paused ? "继续播放" : "暂停播放")
                Button {model.record()} label:{Image(systemName:model.recording ? "stop.circle.fill" : "record.circle").font(.system(size:23)).foregroundStyle(.red)}.disabled(model.busy).help("录音 / 结束录音 · 3").accessibilityLabel(model.recording ? "结束录音" : "开始录音")
                Button {model.toggleLoop()} label:{Image(systemName:"repeat").foregroundStyle(model.loop ? mint : Color.secondary)}.disabled(!canProcess).help("循环试听 · 4 / ⌘L").accessibilityLabel(model.loop ? "关闭循环" : "开启循环")
            }.buttonStyle(.plain).font(.system(size:14)).disabled(model.busy)
            Rectangle().fill(Color.white.opacity(0.1)).frame(width:1,height:36)
            VStack(alignment:.leading,spacing:5) {
                Text(model.recording ? time(model.recordingSeconds) : time(Double(model.playhead)/model.audio.rate)).font(.system(size:21,weight:.light,design:.monospaced)).foregroundStyle(model.recording ? Color.red : Color.white)
                Text(model.isPreviewing ? "效果预听 · 未应用" : model.recording ? "录音中" : model.playing ? "播放中" : model.paused ? "暂停 · 逗号继续" : "停止 · \(playbackScope)").font(.system(size:11)).foregroundStyle(model.isPreviewing ? mint : Color.secondary)
            }.frame(minWidth:170,alignment:.leading)
            Spacer(minLength:0)
            VStack(spacing:4) {
                ForEach(0..<model.audio.channels,id:\.self) {c in meterRow(c)}
                HStack {Text("−60");Spacer();Text("−12");Spacer();Text("0 dBFS")}.font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)
            }.frame(width:218).help("\(model.recording ? "输入峰值" : "源音频峰值，监听音量前") · 点击峰值数字清除保持与削波灯")
            VStack(spacing:5) {
                HStack(spacing:7) {Button {model.monitorMuted.toggle();model.focusWaveform?()} label:{Image(systemName:model.monitorMuted ? "speaker.slash.fill" : "speaker.wave.2")}.buttonStyle(.plain).help("监听静音，不影响保存").accessibilityLabel("监听静音");Slider(value:$model.outputVolume,in:0...1).tint(mint).frame(width:85).accessibilityLabel("监听音量")}
                Text(model.monitorMuted ? "监听已静音" : "监听 \(model.outputVolume>0 ? String(format:"%.1f dB",20*log10(model.outputVolume)) : "−∞ dB")").font(.system(size:10)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal,22).frame(height:88).background(panelColor)
    }
    func meterRow(_ channel:Int)->some View {
        HStack(spacing:5) {
            Text(model.audio.channels==1 ? "M" : channel==0 ? "L" : "R").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).frame(width:9)
            HStack(spacing:2) {ForEach(0..<24) {i in Rectangle().fill(meterColor(channel,index:i)).frame(width:4,height:9)}}
            Button {model.sourceMeter.reset();model.focusWaveform?()} label:{Text(db(model.sourceMeter.holds[channel])).font(.system(size:10,design:.monospaced)).foregroundStyle(model.sourceMeter.clipped[channel] ? Color.red : Color.secondary).frame(width:39,alignment:.trailing)}.buttonStyle(.plain).accessibilityLabel("重置\(channel==0 ? "左" : "右")声道峰值")
            Rectangle().fill(model.sourceMeter.clipped[channel] ? Color.red : Color.white.opacity(0.09)).frame(width:5,height:9)
        }
    }
    func db(_ value:Float)->String {value>0 ? String(format:"%.1f",20*log10(value)) : "−∞"}
    func meterColor(_ channel:Int,index:Int)->Color {let v=model.sourceMeter.values[channel];let d=v>0 ? 20*log10(v) : -96;let on=Float(index)/24<(d+60)/60;return on ? (index>22 ? .red : index>19 ? .yellow : mint) : Color.white.opacity(0.07)}
    var normalizeSheet:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("峰值归一化").font(.system(size:20,weight:.semibold));scopeLabel
            HStack {Text("目标峰值");TextField("目标峰值",value:$model.normalizeDB,format:.number.precision(.fractionLength(1))).frame(width:90);Text("dBFS")}
            HStack {ForEach([-1.0,-3,-6],id:\.self) {target in Button("\(Int(target)) dBFS"){model.normalizeDB=target}}}
            Text("联动所有声道，保持左右声道比例。这里调整样本峰值，不做 LUFS 响度或真峰值标准化。").font(.system(size:12)).foregroundStyle(.secondary)
            HStack {Button("取消"){model.showNormalize=false}.keyboardShortcut(.cancelAction);Button("预听 5 秒"){model.showNormalize=false;model.previewEffect(.normalize(model.normalizeDB),name:"归一化")};Spacer();Button("应用"){model.showNormalize=false;model.effect(.normalize(model.normalizeDB),name:"峰值归一化")}.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)}
        }.padding(28).frame(width:460).background(panelColor)
    }
    var silenceSheet:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("插入静音").font(.system(size:20,weight:.semibold))
            Text(model.selection.isEmpty ? "在光标处插入静音，后续音频后移。" : "用指定时长的静音替换当前选区。").font(.system(size:12)).foregroundStyle(.secondary)
            HStack {Text("时长");TextField("秒",value:$model.silenceSeconds,format:.number).frame(width:110);Text("秒")}
            HStack {Button("取消"){model.showSilence=false}.keyboardShortcut(.cancelAction);Spacer();Button("插入"){model.showSilence=false;model.insertSilence(seconds:model.silenceSeconds)}.keyboardShortcut(.defaultAction)}
        }.padding(28).frame(width:410).background(panelColor)
    }
}
