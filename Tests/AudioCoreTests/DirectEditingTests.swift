import Foundation
import AVFoundation
import AudioCore
extension AudioCoreTests {
    func testSmoothSelectionGain() throws {
        let original=try doc([[Float](repeating:0.25,count:12000),[Float](repeating:-0.125,count:12000)])
        var marked=original;marked.markers=[AudioMarker(frame:4000,name:"内部")]
        for db in [-12.0,6] {
            let gain=SelectionGain(range:1000..<11000,decibels:db),edited=try gain.applied(to:marked,cache:cache),samples=edited.samples(0..<edited.frames)
            XCTAssertEqual(edited.frames,marked.frames);XCTAssertEqual(edited.markers,marked.markers)
            XCTAssertEqual(samples[0][0..<1000],Array(repeating:Float(0.25),count:1000)[...])
            XCTAssertEqual(samples[0][11000..<12000],Array(repeating:Float(0.25),count:1000)[...])
            XCTAssertEqual(samples[0][1000],0.25);XCTAssertEqual(samples[0][10999],0.25)
            XCTAssertEqual(samples[0][6000],Float(0.25*pow(10,db/20)),accuracy:1e-7)
            for i in 1000..<11000 {XCTAssertEqual(samples[1][i],samples[0][i] * -0.5)}
            var jump:Float=0
            for i in 1000..<11001 {jump=max(jump,abs(samples[0][i]-samples[0][i-1]))}
            XCTAssertFalse(jump>0.001)
        }
        for n in [1,2,3,12,719] {
            let gain=SelectionGain(range:100..<100+n,decibels:6),edited=try gain.applied(to:marked,cache:cache)
            XCTAssertEqual(edited.frames,marked.frames);XCTAssertEqual(edited.samples(100..<101)[0][0],0.25)
            XCTAssertEqual(edited.samples(99+n..<100+n)[0][0],0.25)
        }
        XCTAssertEqual(try SelectionGain(range:0..<100,decibels:0).applied(to:original,cache:cache).revision,original.revision)
        XCTAssertThrowsError(try SelectionGain(range:0..<100,decibels:.nan).applied(to:original,cache:cache))
    }
    func testClipRateChannelsFades() throws {
        for rate in [44100.0,48000,96000] {for channels in [1,2] {
            print("CLIP MATRIX",rate,channels)
            let d=try signal(rate:rate,channels:channels,frames:Int(rate)),range=Int(rate/4)..<Int(rate*0.75)
            let url=cache.folder.appendingPathComponent("clip-\(rate)-\(channels).wav"),before=d.samples(range)
            try ClipExporter.write(d,range:range,to:url)
            let format=try SourceEncoding(inspecting:url),back=try cache.read(url),samples=back.samples(0..<back.frames)
            XCTAssertEqual(format.rate,48000);XCTAssertEqual(format.channels,2);XCTAssertEqual(format.bits,24);XCTAssertEqual(back.frames,24000)
            XCTAssertEqual(samples[0][0],0);XCTAssertEqual(samples[0].last!,0)
            for i in 1000..<23000 {let expected=Float(sin(Double(i)*2*Double.pi*440/48000))*0.6;XCTAssertEqual(samples[0][i],expected,accuracy:0.015)}
            if channels==1 {XCTAssertEqual(samples[0],samples[1])}
            else {XCTAssertEqual(samples[1][3000],samples[0][3000]*0.5,accuracy:1e-6)}
            XCTAssertEqual(d.samples(range),before)
            XCTAssertThrowsError(try ClipExporter.write(d,range:range,to:url))
        }}
        let constant=try doc([[Float](repeating:0.5,count:2000)])
        let rendered=try ClipExporter.render(constant,range:0..<2000,cache:cache),v=rendered.samples(0..<2000)[0]
        XCTAssertEqual(v[0],0);XCTAssertEqual(v[360],0.25,accuracy:1e-6);XCTAssertEqual(v[720],0.5,accuracy:1e-6);XCTAssertEqual(v[1999],0)
        for rate in [44100.0,96000] {for length in [1,2,3,12,100] {
            print("SHORT CLIP",rate,length)
            let d=try doc([[Float](repeating:0.4,count:length)],rate:rate),r=try ClipExporter.render(d,range:0..<length,cache:cache)
            XCTAssertEqual(r.frames,max(1,Int((Double(length)*48000/rate).rounded())))
            XCTAssertEqual(r.samples(0..<1)[0][0],0);XCTAssertEqual(r.samples(r.frames-1..<r.frames)[0][0],0)
        }}
    }
    func testClipAliasRejectionAndPendingGain() throws {
        let frames=96000,samples=(0..<frames).map {Float(sin(Double($0)*2*Double.pi*30000/96000))*0.5}
        let source=try doc([samples],rate:96000),result=try ClipExporter.render(source,range:0..<frames,cache:cache)
        let output=result.samples(2000..<46000)[0],rms=sqrt(output.reduce(0.0){$0+Double($1*$1)}/Double(output.count))
        XCTAssertFalse(rms>0.005)
        let d=try signal(),range=1000..<40000,gain=SelectionGain(range:range,decibels:-6)
        let preview=try ClipExporter.render(d,range:range,gain:gain,cache:cache)
        let applied=try gain.applied(to:d,cache:cache),committed=try ClipExporter.render(applied,range:range,cache:cache)
        XCTAssertEqual(preview.samples(0..<preview.frames),committed.samples(0..<committed.frames))
    }
    func testUsageNotesPersistenceAndUpgrade() throws {
        let url=cache.folder.appendingPathComponent("建议/使用建议.md"),body="- 选区试听需要更顺手\n\n中文建议 **保留**\n"
        let a=try UsageNotesStore(url:url,version:"0.4.0");try a.save(body)
        XCTAssertEqual(try UsageNotesStore(url:url,version:"0.4.0").text,body)
        let upgraded=try UsageNotesStore(url:url,version:"0.5.0")
        XCTAssertEqual(upgraded.text,body)
        let raw=try String(contentsOf:url);XCTAssertFalse(!raw.contains("当前版本：0.5.0"));XCTAssertFalse(raw.contains("当前版本：0.4.0"))
        let imported=cache.folder.appendingPathComponent("外来.md");try "- 拖入补充建议".write(to:imported,atomically:true,encoding:.utf8)
        let both=try upgraded.importMarkdown(imported);XCTAssertEqual(both,body+"\n\n- 拖入补充建议")
        XCTAssertEqual(try UsageNotesStore(url:url,version:"0.5.0").text,both)
        let fake=cache.folder.appendingPathComponent("错误.wav");try Data([0xff]).write(to:fake)
        XCTAssertThrowsError(try upgraded.importMarkdown(fake));XCTAssertEqual(upgraded.text,both)
    }
}
