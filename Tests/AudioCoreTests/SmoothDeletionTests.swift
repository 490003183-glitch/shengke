import Foundation
import AudioCore

extension AudioCoreTests {
    func testDeletionCrossfade() throws {
        for rate in [44100.0,48000,96000] {for channels in [1,2] {
            let side=Int(rate/10),removed=701,fade=Int((rate*0.015).rounded())
            // The removed material is deliberately much louder: it must not enter the join.
            let input=Array(repeating:Float(0.6),count:side)+Array(repeating:Float(8),count:removed)+Array(repeating:Float(-0.4),count:side)
            var original=try doc(channels==1 ? [input] : [input,input.map{-$0*0.5}],rate:rate)
            original.markers=[AudioMarker(frame:side-fade,name:"left"),AudioMarker(frame:side,name:"deleted-start"),AudioMarker(frame:side+100,name:"deleted"),AudioMarker(frame:side+removed+10,name:"right"),AudioMarker(frame:input.count,name:"end")]
            let result=try SmoothDeletion.apply(original,range:side..<side+removed,cache:cache),audio=result.audio,samples=audio.samples(0..<audio.frames)
            XCTAssertEqual(audio.frames,2*side-fade);XCTAssertEqual(result.overlapFrames,fade);XCTAssertEqual(result.cursor,side-fade)
            XCTAssertEqual(samples[0][0..<side-fade],input[0..<side-fade])
            XCTAssertEqual(Array(samples[0][side...]),Array(input[(side+removed+fade)...]))
            XCTAssertEqual(samples[0][side-fade],0.6);XCTAssertEqual(samples[0][side-1],-0.4)
            let maximumJump=zip(samples[0],samples[0].dropFirst()).map{abs($1-$0)}.max()!
            XCTAssertFalse(maximumJump>0.003)
            XCTAssertFalse(samples[0].contains{$0 > 0.6 || $0 < -0.4})
            if channels==2 {for i in 0..<audio.frames {XCTAssertEqual(samples[1][i],-samples[0][i]*0.5)}}
            XCTAssertEqual(audio.markers.map{$0.frame},[side-fade,side-fade+10,audio.frames])
            XCTAssertEqual(original.samples(0..<original.frames)[0],input)
            let file=cache.folder.appendingPathComponent("delete-\(rate)-\(channels).wav")
            try FileAudioWriter.write(audio,to:file,encoding:.wav(rate:rate,channels:channels))
            let back=try cache.read(file);XCTAssertEqual(back.frames,audio.frames)
            for c in 0..<channels {for i in 0..<audio.frames {XCTAssertEqual(back.samples(i..<i+1)[c][0],samples[c][i],accuracy:1.0/8388608)}}
        }}
        let constant=try doc([Array(repeating:Float(0.9),count:4000)])
        let same=try SmoothDeletion.apply(constant,range:1500..<2500,cache:cache).audio
        for sample in same.samples(0..<same.frames)[0] {XCTAssertEqual(sample,0.9,accuracy:1e-7)}
    }
    func testDeletionHeadFade() throws {
        for rate in [44100.0,48000,96000] {
            let length=Int(rate*0.1),fade=Int((rate*0.015).rounded()),removed=91
            var original=try doc([Array(repeating:Float(0.8),count:length+removed),Array(repeating:Float(-0.4),count:length+removed)],rate:rate)
            original.markers=[AudioMarker(frame:0,name:"deleted"),AudioMarker(frame:removed+10,name:"retained")]
            let result=try SmoothDeletion.apply(original,range:0..<removed,cache:cache),audio=result.audio,a=audio.samples(0..<audio.frames)
            XCTAssertEqual(audio.frames,length);XCTAssertEqual(result.cursor,0);XCTAssertEqual(result.overlapFrames,0)
            XCTAssertEqual(audio.markers.map{$0.frame},[10]);XCTAssertEqual(a[0][0],0);XCTAssertEqual(a[0][fade-1],0.8)
            XCTAssertEqual(Array(a[0][fade...]),Array(repeating:Float(0.8),count:length-fade))
            for i in 1..<fade {XCTAssertFalse(a[0][i]<a[0][i-1]);XCTAssertEqual(a[1][i],-a[0][i]*0.5)}
        }
    }
    func testDeletionShortEdgesAndHistory() throws {
        for left in [0,1,2,7,720] {for right in [0,1,2,7,720] {
            let original=try doc([Array(repeating:Float(0.5),count:left)+[10]+Array(repeating:Float(-0.5),count:right)])
            let range=left..<left+1,result=try SmoothDeletion.apply(original,range:range,cache:cache)
            XCTAssertEqual(result.audio.frames,left+right-(left>0 && right>0 ? min(left,right,720) : 0))
            XCTAssertFalse(result.cursor<0 || result.cursor>result.audio.frames)
            XCTAssertFalse(result.audio.samples(0..<result.audio.frames).flatMap{$0}.contains{!$0.isFinite || abs($0)>0.5})
            if left==0 && right>0 {XCTAssertEqual(result.audio.samples(0..<1)[0][0],0)}
            let history=EditHistory(EditorSnapshot(audio:original,selection:range))
            history.commit(EditorSnapshot(audio:result.audio,selection:result.cursor..<result.cursor),name:"delete")
            history.undo();XCTAssertEqual(history.state.audio.samples(0..<original.frames),original.samples(0..<original.frames));XCTAssertEqual(history.state.selection,range)
            history.redo();XCTAssertEqual(history.state.audio.samples(0..<result.audio.frames),result.audio.samples(0..<result.audio.frames))
        }}
        let original=try doc([[0.1,0.2,0.3]])
        XCTAssertEqual(try SmoothDeletion.apply(original,range:1..<1,cache:cache).audio.revision,original.revision)
        XCTAssertEqual(try SmoothDeletion.apply(original,range:1..<3,cache:cache).audio.samples(0..<1),[[0.1]])
        XCTAssertThrowsError(try SmoothDeletion.apply(original,range:0..<4,cache:cache))
        XCTAssertThrowsError(try SmoothDeletion.apply(original,range:(-1)..<1,cache:cache))
    }
}
