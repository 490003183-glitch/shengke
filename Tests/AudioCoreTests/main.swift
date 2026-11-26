import Foundation
import AudioCore
var failedAssertions=0
func failure(_ message:String,file:StaticString,line:UInt) { failedAssertions += 1; if failedAssertions<25 { print("FAIL \(file):\(line) \(message)") } }
func XCTAssertEqual<T:Equatable>(_ a:T,_ b:T,file:StaticString=#filePath,line:UInt=#line) { if a != b {failure("\(a) != \(b)",file:file,line:line)} }
func XCTAssertEqual<T:BinaryFloatingPoint>(_ a:T,_ b:T,accuracy:T,file:StaticString=#filePath,line:UInt=#line) { if !(abs(a-b)<=accuracy) {failure("\(a) != \(b), tolerance \(accuracy)",file:file,line:line)} }
func XCTAssertNil<T>(_ a:T?,file:StaticString=#filePath,line:UInt=#line) { if a != nil {failure("Expected nil",file:file,line:line)} }
func XCTAssertFalse(_ a:Bool,file:StaticString=#filePath,line:UInt=#line) { if a {failure("Expected false",file:file,line:line)} }
func XCTAssertGreaterThan<T:Comparable>(_ a:T,_ b:T,file:StaticString=#filePath,line:UInt=#line) { if a<=b {failure("\(a) <= \(b)",file:file,line:line)} }
func XCTAssertThrowsError<T>(_ expr:@autoclosure () throws -> T,file:StaticString=#filePath,line:UInt=#line) { do { _=try expr();failure("Expected an error",file:file,line:line) } catch {} }
let tests=AudioCoreTests()
let cases:[(String,() throws -> Void)]=[
("selection gain continuous boundaries / stereo / short ranges",tests.testSmoothSelectionGain),
("drag clip 48k 24bit stereo / fades / short resampling",tests.testClipRateChannelsFades),
("clip anti-alias resampling / pending gain snapshot",tests.testClipAliasRejectionAndPendingGain),
("usage notes persistence / version upgrade / Markdown import",tests.testUsageNotesPersistenceAndUpgrade),
("cut/paste stereo + markers",tests.testCutPasteExactStereoAndMarkers),
("replace/crop boundaries",tests.testReplacementAndCrop),
("undo/redo + selection + markers",tests.testHistoryRestoresSamplesSelectionAndMarkers),
("fade/gain/invalid parameters",tests.testFadeGainAndUnselectedSamples),
("normalize/silence/stereo balance",tests.testNormalizeSilenceAndStereoBalance),
("reverse + marker preservation",tests.testReverseTwiceAndEffectMarkerPreservation),
("peak cache impulse accuracy",tests.testPeakPyramidNeverLosesImpulse),
("PCM 16/24/float + AIFF roundtrip matrix",tests.testPCMExportRoundTripsAndSelection),
("AAC roundtrip",tests.testAACExportReadableAndDuration),
("export failure preserves target",tests.testExportFailurePreservesExistingFile),
("float overload + corrupt input",tests.testFloatExportPreservesOverloadAndCorruptInputFails),
("time formats/sample roundtrip + invalid inputs",tests.testTimeUnitsRoundTrip),
("selection anchor reversal",tests.testSelectionAnchorReversal),
("viewport anchored zoom + limits",tests.testViewportAnchorAndLimits),
("L/R meter + peak hold + clip reset",tests.testSeparateMeterHoldClipAndReset),
("click tolerance / precise boundary drag",tests.testClickToleranceAndPreciseEdgeDrag),
("native source encoding copy/overwrite matrix",tests.testSourceEncodingCopyAndOverwrite),
("actual AIFF container / 24-bit samples preserved",tests.testActualAIFFContainerPreservation),
("MP3 CBR/VBR source encoding roundtrip",tests.testMP3SourceEncodingRoundtrip),
("ALAC/FLAC native lossless preservation",tests.testNativeLosslessSourcePreservation),
("outside modification + failed save preserve original",tests.testSourceModificationAndFailedSave),
("WAV conversion writes/validates before trash",tests.testConversionOrderingAndFrames),
("conversion collision + trash failure preserve files",tests.testConversionCollisionAndTrashFailure)

]
for (name,run) in cases {
 let before=failedAssertions
 do {try tests.setUpWithError();try run()} catch {failedAssertions += 1;print("FAIL \(name): \(error)")}
 tests.tearDown();print("\(failedAssertions==before ? "PASS" : "FAIL") \(name)")
}
print("\(cases.count) cases, \(failedAssertions) failures")
if CommandLine.arguments.contains("--long") {
    do { try runLongBenchmark() } catch { failedAssertions += 1; print("FAIL long benchmark: \(error)") }
}
exit(failedAssertions == 0 ? 0 : 1)

func runLongBenchmark() throws {
    let base=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("tmp")
    try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
    let cache=try AudioCache(base:base)
    let begin=Date(), frames=48000*3600
    let asset=try cache.makeAsset(rate:48000,channels:2,frames:frames) { start,count in
        let samples=(0..<count).map { i -> Float in ((start+i)%480)<240 ? 0.3 : -0.3 }
        return [samples,samples]
    }
    let indexed=Date()
    let doc=AudioDocument(rate:48000,channels:2,pieces:[Piece(asset:asset,offset:0,count:frames)])
    let history=EditHistory(EditorSnapshot(audio:doc))
    let edits=Date()
    for _ in 0..<20 { let d=history.state.audio; history.commit(EditorSnapshot(audio:d.replacing(48000..<96000,with:[])),name:"cut") }
    for _ in 0..<20 { history.undo() }
    XCTAssertEqual(history.state.audio.frames,frames)
    let edited=Date()
    for channel in 0..<2 { for x in 0..<1200 {
        let p=doc.peak((x*frames/1200)..<((x+1)*frames/1200),channel:channel)
        XCTAssertEqual(p.high,Float(0.3));XCTAssertEqual(p.low,Float(-0.3))
    } }
    let viewed=Date()
    let files=try FileManager.default.contentsOfDirectory(at:cache.folder,includingPropertiesForKeys:[.fileSizeKey])
    let bytes=try files.reduce(0) { try $0 + $1.resourceValues(forKeys:[.fileSizeKey]).fileSize! }
    print(String(format:"LONG 60 min / 48 kHz / stereo: generate+index %.3fs; 20 edits+undo %.4fs; 1200px stereo peaks %.4fs; cache %d bytes; files %d",indexed.timeIntervalSince(begin),edited.timeIntervalSince(edits),viewed.timeIntervalSince(edited),bytes,files.count))
    XCTAssertEqual(bytes,frames*2*4)
}
