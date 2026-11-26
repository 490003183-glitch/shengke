import Foundation
import AVFoundation
import AudioCore

final class AudioCoreTests {
    var cache: AudioCache!
    func setUpWithError() throws { cache=try AudioCache() }
    func tearDown() { cache=nil }
    func doc(_ samples:[[Float]],rate:Double=48000) throws -> AudioDocument {
        let a=try cache.makeAsset(rate:rate,channels:samples.count,frames:samples[0].count) { start,count in samples.map{Array($0[start..<start+count])} }
        return AudioDocument(rate:rate,channels:samples.count,pieces:[Piece(asset:a,offset:0,count:a.frames)])
    }
    func testCutPasteExactStereoAndMarkers() throws {
        var d=try doc([[0,1,2,3,4,5],[10,11,12,13,14,15]])
        d.markers=[AudioMarker(frame:1,name:"前"),AudioMarker(frame:3,name:"内"),AudioMarker(frame:5,name:"后")]
        let clip=d.sliced(2..<4),cut=d.replacing(2..<4,with:[])
        XCTAssertEqual(cut.samples(0..<4),[[0,1,4,5],[10,11,14,15]])
        XCTAssertEqual(cut.markers.map(\.frame),[1,3])
        let pasted=cut.replacing(2..<2,with:clip)
        XCTAssertEqual(pasted.samples(0..<6),d.samples(0..<6))
        XCTAssertEqual(pasted.frames,6)
    }
    func testReplacementAndCrop() throws {
        var d=try doc([[0,1,2,3,4,5]])
        d.markers=[AudioMarker(frame:2,name:"入"),AudioMarker(frame:4,name:"出")]
        let small=try doc([[8,9,10]])
        XCTAssertEqual(d.replacing(1..<5,with:small.pieces).samples(0..<5),[[0,8,9,10,5]])
        let cropped=d.cropped(2..<5)
        XCTAssertEqual(cropped.samples(0..<3),[[2,3,4]])
        XCTAssertEqual(cropped.markers.map(\.frame),[0,2])
        XCTAssertEqual(d.replacing(0..<6,with:[]).frames,0)
    }
    func testHistoryRestoresSamplesSelectionAndMarkers() throws {
        var d=try doc([[0,1,2,3]])
        d.markers=[AudioMarker(frame:3,name:"末")]
        let history=EditHistory(EditorSnapshot(audio:d,selection:1..<3))
        history.commit(EditorSnapshot(audio:d.replacing(1..<3,with:[]),selection:1..<1),name:"删除")
        history.undo()
        XCTAssertEqual(history.state.audio.samples(0..<4),[[0,1,2,3]])
        XCTAssertEqual(history.state.selection,1..<3)
        XCTAssertEqual(history.state.audio.markers,d.markers)
        history.redo();XCTAssertEqual(history.state.audio.frames,2)
        history.undo();history.commit(EditorSnapshot(audio:d.cropped(0..<1)),name:"裁剪")
        XCTAssertNil(history.redoName)
    }
    func testFadeGainAndUnselectedSamples() throws {
        let d=try doc([[1,1,1,1,1,1],[0.5,0.5,0.5,0.5,0.5,0.5]])
        let faded=try d.transformed(1..<5,effect:.fadeIn,cache:cache).samples(0..<6)
        let expected:[Float] = [1,0,1.0/3,2.0/3,1,1]
        for (a,b) in zip(faded[0],expected) { XCTAssertEqual(a,b,accuracy:1e-6) }
        let gain=try d.transformed(2..<4,effect:.gain(6.020599913),cache:cache).samples(0..<6)
        XCTAssertEqual(gain[0][2],2,accuracy:1e-6);XCTAssertEqual(gain[0][1],1)
        let single=try d.transformed(2..<3,effect:.fadeOut,cache:cache)
        XCTAssertEqual(single.samples(2..<3),[[0],[0]])
        XCTAssertThrowsError(try d.transformed(0..<6,effect:.gain(.nan),cache:cache))
    }
    func testNormalizeSilenceAndStereoBalance() throws {
        let d=try doc([[-0.5,0.25],[0.25,-0.1]])
        let result=try d.transformed(0..<2,effect:.normalize(-1),cache:cache).samples(0..<2)
        XCTAssertEqual(20*log10(abs(result[0][0])),-1,accuracy:0.001)
        XCTAssertEqual(result[1][0]/result[0][0],-0.5,accuracy:1e-6)
        let silence=try doc([[0,0,0]])
        XCTAssertEqual(try silence.transformed(0..<3,effect:.normalize(-1),cache:cache).samples(0..<3),[[0,0,0]])
    }
    func testReverseTwiceAndEffectMarkerPreservation() throws {
        var d=try doc([[1,2,3,4,5]])
        d.markers=[AudioMarker(frame:2,name:"中")]
        let first=try d.transformed(1..<4,effect:.reverse,cache:cache)
        XCTAssertEqual(first.samples(0..<5),[[1,4,3,2,5]])
        XCTAssertEqual(first.markers,d.markers)
        let twice=try first.transformed(1..<4,effect:.reverse,cache:cache)
        XCTAssertEqual(twice.samples(0..<5),d.samples(0..<5))
    }
    func testPeakPyramidNeverLosesImpulse() throws {
        var samples=[Float](repeating:0,count:100000)
        samples[255]=0.9;samples[65536] = -1.2;samples[99999]=0.6
        let d=try doc([samples])
        for range in [0..<100000,250..<257,65500..<66000,99990..<100000,256..<1024] {
            let p=d.peak(range,channel:0)
            XCTAssertEqual(p.high,max(0,samples[range].max()!))
            XCTAssertEqual(p.low,min(0,samples[range].min()!))
        }
    }
    func testPCMExportRoundTripsAndSelection() throws {
        for rate in [44100.0,48000] { for channels in [1,2] {
            let samples=(0..<channels).map { c in (0..<20000).map { Float(sin(Double($0)*0.071+Double(c))*0.7) } }
            let d=try doc(samples,rate:rate)
            for format in [ExportFormat.wav16,.wav24,.wavFloat,.aiff24] {
                let url=cache.folder.appendingPathComponent("回读-\(rate)-\(channels)-\(format.rawValue).\(format.ext)")
                try AudioExporter.write(d,range:101..<19101,to:url,format:format)
                let back=try cache.read(url)
                XCTAssertEqual(back.frames,19000);XCTAssertEqual(back.rate,rate);XCTAssertEqual(back.channels,channels)
                let result=back.samples(0..<back.frames)
                let error:Float = format == .wav16 ? 1.0/32768 : format == .wavFloat ? 0 : 1.0/8388608
                for c in 0..<channels { for i in 0..<back.frames { XCTAssertEqual(result[c][i],samples[c][i+101],accuracy:error) } }
            }
        } }
    }
    func testAACExportReadableAndDuration() throws {
        let d=try doc([(0..<48000).map{Float(sin(Double($0)*0.05)*0.5)}])
        let url=cache.folder.appendingPathComponent("test.m4a")
        try AudioExporter.write(d,range:0..<d.frames,to:url,format:.aac)
        let back=try cache.read(url)
        XCTAssertEqual(back.channels,1);XCTAssertEqual(back.duration,1,accuracy:0.05)
        XCTAssertGreaterThan(back.peak(0..<back.frames,channel:0).high,0.4)
    }
    func testExportFailurePreservesExistingFile() throws {
        let d=try doc([[0.1,0.2,0.3]])
        let url=cache.folder.appendingPathComponent("existing.wav")
        let before=Data("original file".utf8);try before.write(to:url)
        XCTAssertThrowsError(try AudioExporter.write(d,range:0..<0,to:url,format:.wav16))
        XCTAssertEqual(try Data(contentsOf:url),before)
        let bad=cache.folder.appendingPathComponent("missing/out.wav")
        XCTAssertThrowsError(try AudioExporter.write(d,range:0..<3,to:bad,format:.wav16))
        XCTAssertFalse(FileManager.default.fileExists(atPath:bad.path))
    }
    func testFloatExportPreservesOverloadAndCorruptInputFails() throws {
        let d=try doc([[1.5,-1.25,0.3]])
        let url=cache.folder.appendingPathComponent("float.wav")
        try AudioExporter.write(d,range:0..<3,to:url,format:.wavFloat)
        XCTAssertEqual(try cache.read(url).samples(0..<3),[[1.5,-1.25,0.3]])
        let bad=cache.folder.appendingPathComponent("broken.wav");try Data("bad".utf8).write(to:bad)
        XCTAssertThrowsError(try cache.read(bad))
    }
}
