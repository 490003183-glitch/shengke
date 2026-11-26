import Foundation
import AudioCore
extension AudioCoreTests {
    func testTimeUnitsRoundTrip() throws {
        for rate in [8000.0,44100,48000,96000,192000,384000] {
            for f in [0,1,2,47,44100,2879999,48000*3600+1] {
                XCTAssertEqual(try TimeUnit.clock.parse(TimeUnit.clock.format(f,rate:rate),rate:rate),f)
                XCTAssertEqual(try TimeUnit.samples.parse(String(f),rate:rate),f)
            }
        }
        XCTAssertEqual(try TimeUnit.clock.parse("1:02:03.5",rate:48000),178728000)
        XCTAssertEqual(try TimeUnit.clock.parse("60",rate:48000),2880000)
        for invalid in ["-1","1:60","1.2:30","NaN","inf","","1::2","1:2:3:4","1e300"] {
            XCTAssertThrowsError(try TimeUnit.clock.parse(invalid,rate:48000))
        }
        for invalid in ["-1","1.2","NaN","9223372036854775808"] {XCTAssertThrowsError(try TimeUnit.samples.parse(invalid,rate:48000))}
    }
    func testSelectionAnchorReversal() {
        var s=SelectionGesture(anchor:10,head:10)
        s.move(by:5,limit:30);XCTAssertEqual(s.range,10..<15)
        s.move(by:-8,limit:30);XCTAssertEqual(s.range,7..<10)
        s.move(by:4,limit:30);XCTAssertEqual(s.range,10..<11)
        s.move(by:-100,limit:30);XCTAssertEqual(s.head,0);XCTAssertEqual(s.anchor,10)
        s.move(by:100,limit:30);XCTAssertEqual(s.head,30)
    }
    func testViewportAnchorAndLimits() {
        let v=Viewport(start:100,length:800)
        let zoom=v.zoomed(factor:2,anchor:300,total:2000)
        XCTAssertEqual(zoom.start,200);XCTAssertEqual(zoom.length,400)
        XCTAssertEqual((300-v.start)/v.length,(300-zoom.start)/zoom.length)
        let sample=v.zoomed(factor:1e20,anchor:300,total:2000);XCTAssertEqual(sample.length,1)
        let fit=v.zoomed(factor:0.01,anchor:300,total:2000);XCTAssertEqual(fit.start,0);XCTAssertEqual(fit.length,2000)
        XCTAssertEqual(v.zoomed(factor:.nan,anchor:300,total:2000).length,800)
    }
    func testSeparateMeterHoldClipAndReset() {
        var m=SourceMeter();m.ingest([0.25,1.2]);XCTAssertEqual(m.values,[0.25,1.2]);XCTAssertEqual(m.clipped,[false,true])
        m.ingest([0.5,0]);XCTAssertEqual(m.holds,[0.5,1.2]);XCTAssertEqual(m.values[1],0.864,accuracy:0.0001)
        m.stop();XCTAssertEqual(m.values,[0,0]);XCTAssertEqual(m.clipped,[false,true])
        m.reset();XCTAssertEqual(m.holds,[0,0]);XCTAssertEqual(m.clipped,[false,false])
        m.ingest([.nan]);XCTAssertEqual(m.values,[0,0])
    }
    func testClickToleranceAndPreciseEdgeDrag() {
        var click=SelectionDrag(startX:100)
        XCTAssertFalse(click.update(x:100.23));XCTAssertFalse(click.update(x:102.9))
        XCTAssertEqual(click.update(x:104),true);XCTAssertEqual(click.update(x:100.2),true)
        var edge=SelectionDrag(startX:100,precise:true)
        XCTAssertEqual(edge.update(x:100.23),true)
    }
}
