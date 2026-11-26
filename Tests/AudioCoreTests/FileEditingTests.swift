import Foundation
import AVFoundation
import AudioCore
extension AudioCoreTests {
    func signal(rate:Double=48000,channels:Int=2,frames:Int=48000) throws -> AudioDocument {
        try doc((0..<channels).map {c in (0..<frames).map {i in Float(sin(Double(i)*2*Double.pi*440/rate))*(c==0 ? 0.6 : 0.3)}},rate:rate)
    }
    func testSourceEncodingCopyAndOverwrite() throws {
        for format in [ExportFormat.wav16,.wav24,.wavFloat,.aiff24,.aac] {
            let seed=try signal(),original=cache.folder.appendingPathComponent("原件-\(format.rawValue).\(format.ext)")
            try AudioExporter.write(seed,range:0..<seed.frames,to:original,format:format)
            print("SOURCE MATRIX \(format.rawValue)")
            let source=try SourceAudioFile(original),before=try Data(contentsOf:original)
            let loaded=try cache.read(original),edit=loaded.cropped(1200..<25200)
            let copy=cache.folder.appendingPathComponent("副本-\(format.rawValue).\(format.ext)")
            try FileAudioWriter.copy(edit,source:source,to:copy)
            XCTAssertEqual(try Data(contentsOf:original),before)
            let encoded=try SourceEncoding(inspecting:copy)
            XCTAssertEqual(encoded.codec,source.encoding.codec);XCTAssertEqual(encoded.container,source.encoding.container);XCTAssertEqual(encoded.rate,source.encoding.rate);XCTAssertEqual(encoded.channels,source.encoding.channels)
            XCTAssertEqual(encoded.bits,source.encoding.bits);XCTAssertEqual(encoded.isFloat,source.encoding.isFloat)
            XCTAssertEqual(try cache.read(copy).duration,0.5,accuracy:format == .aac ? 0.075 : 0)
            XCTAssertThrowsError(try FileAudioWriter.copy(edit,source:source,to:original))
            try FileAudioWriter.write(edit,to:original,encoding:source.encoding,overwriting:source)
            XCTAssertEqual(try cache.read(original).duration,0.5,accuracy:format == .aac ? 0.075 : 0)
            let replaced=try SourceEncoding(inspecting:original);XCTAssertEqual(replaced.codec,source.encoding.codec);XCTAssertEqual(replaced.bits,source.encoding.bits)
        }
        for (bits,floating) in [(32,false),(64,true)] {
            print("SOURCE MATRIX WAV \(bits) float=\(floating)")
            let seed=try signal(channels:1),url=cache.folder.appendingPathComponent("\(bits)-\(floating).wav")
            try FileAudioWriter.write(seed,to:url,encoding:.wav(rate:seed.rate,channels:1,bits:bits,isFloat:floating))
            let source=try SourceAudioFile(url),edited=try cache.read(url).cropped(100..<1000)
            try FileAudioWriter.write(edited,to:url,encoding:source.encoding,overwriting:source)
            XCTAssertEqual(try SourceEncoding(inspecting:url).bits,bits);XCTAssertEqual(try cache.read(url).frames,900)
        }
    }
    func testActualAIFFContainerPreservation() throws {
        let d=try signal(),input=cache.folder.appendingPathComponent("seed.wav"),url=cache.folder.appendingPathComponent("native.aiff")
        try AudioExporter.write(d,range:0..<d.frames,to:input,format:.wav24)
        let conversion=Process();conversion.executableURL=URL(fileURLWithPath:"/usr/bin/afconvert");conversion.arguments=["-f","AIFF","-d","BEI24",input.path,url.path]
        try conversion.run();conversion.waitUntilExit();XCTAssertEqual(conversion.terminationStatus,0)
        let source=try SourceAudioFile(url),loaded=try cache.read(url),before=try Data(contentsOf:url),edited=try loaded.transformed(1200..<24000,effect:.gain(-6),cache:cache)
        XCTAssertEqual(source.encoding.container,kAudioFileAIFFType)
        let copy=cache.folder.appendingPathComponent("native-copy.aiff")
        try FileAudioWriter.copy(edited,source:source,to:copy)
        XCTAssertEqual(try Data(contentsOf:url),before)
        try FileAudioWriter.write(edited,to:url,encoding:source.encoding,overwriting:source)
        for result in [copy,url] {
            let format=try SourceEncoding(inspecting:result),back=try cache.read(result)
            XCTAssertEqual(format.container,kAudioFileAIFFType);XCTAssertEqual(format.bits,24);XCTAssertEqual(back.frames,d.frames)
            let actual=back.samples(0..<d.frames),expected=edited.samples(0..<d.frames)
            for c in 0..<d.channels {for frame in 0..<d.frames {XCTAssertEqual(actual[c][frame],expected[c][frame],accuracy:1.0/8388608)}}
        }
    }
    func testMP3SourceEncodingRoundtrip() throws {
        for rate in [44100.0,48000] {for channels in [1,2] {for variable in [false,true] {
            let d=try signal(rate:rate,channels:channels,frames:Int(rate)),url=cache.folder.appendingPathComponent("mp3-\(rate)-\(channels)-\(variable).mp3")
            try FileAudioWriter.write(d,to:url,encoding:.mp3(rate:rate,channels:channels,bitRate:192000,variable:variable))
            let source=try SourceAudioFile(url),back=try cache.read(url)
            XCTAssertEqual(source.encoding.fileExtension,"mp3");XCTAssertEqual(source.encoding.rate,rate);XCTAssertEqual(source.encoding.channels,channels);XCTAssertEqual(source.encoding.variableMP3,variable)
            XCTAssertEqual(back.duration,1,accuracy:0.075);XCTAssertGreaterThan(back.peak(0..<back.frames,channel:0).high,0.4)
            let shortened=back.cropped(100..<Int(rate/2))
            try FileAudioWriter.write(shortened,to:url,encoding:source.encoding,overwriting:source)
            let replaced=try SourceAudioFile(url);XCTAssertEqual(replaced.encoding.codec,source.encoding.codec);XCTAssertEqual(replaced.encoding.variableMP3,variable)
            XCTAssertEqual(try cache.read(url).duration,shortened.duration,accuracy:0.075)
        }}}
    }
    func nativeSeed(_ doc:AudioDocument,to url:URL,format:AudioFormatID) throws {
        let settings:[String:Any]=[AVFormatIDKey:format,AVSampleRateKey:doc.rate,AVNumberOfChannelsKey:doc.channels,AVEncoderBitDepthHintKey:24]
        let file=try AVAudioFile(forWriting:url,settings:settings,commonFormat:.pcmFormatFloat32,interleaved:false)
        let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(doc.frames))!;buffer.frameLength=buffer.frameCapacity
        let samples=doc.samples(0..<doc.frames)
        for c in 0..<doc.channels {samples[c].withUnsafeBufferPointer {buffer.floatChannelData![c].update(from:$0.baseAddress!,count:doc.frames)}}
        try file.write(from:buffer)
    }
    func testNativeLosslessSourcePreservation() throws {
        for (codec,ext) in [(kAudioFormatAppleLossless,"m4a"),(kAudioFormatFLAC,"flac")] {
            let d=try signal(),url=cache.folder.appendingPathComponent("lossless.\(ext)")
            try nativeSeed(d,to:url,format:codec)
            let source=try SourceAudioFile(url),loaded=try cache.read(url),edit=loaded.cropped(100..<24000)
            try FileAudioWriter.write(edit,to:url,encoding:source.encoding,overwriting:source)
            XCTAssertEqual(try SourceEncoding(inspecting:url).codec,codec)
            XCTAssertEqual(try cache.read(url).samples(0..<edit.frames),edit.samples(0..<edit.frames))
        }
    }
    func testSourceModificationAndFailedSave() throws {
        let d=try signal(),url=cache.folder.appendingPathComponent("original.wav")
        try FileAudioWriter.write(d,to:url,encoding:.wav(rate:d.rate,channels:2,bits:16))
        let source=try SourceAudioFile(url),original=try Data(contentsOf:url)
        XCTAssertThrowsError(try FileAudioWriter.write(AudioDocument(),to:url,encoding:source.encoding,overwriting:source))
        XCTAssertEqual(try Data(contentsOf:url),original)
        try Data("external modification".utf8).write(to:url)
        XCTAssertThrowsError(try FileAudioWriter.write(d,to:url,encoding:source.encoding,overwriting:source))
        XCTAssertEqual(try String(contentsOf:url),"external modification")
        XCTAssertThrowsError(try FileAudioWriter.convertToWAV(d,source:source))
    }
    func testConversionOrderingAndFrames() throws {
        let d=try signal(),url=cache.folder.appendingPathComponent("convert.aiff")
        try AudioExporter.write(d,range:0..<d.frames,to:url,format:.aiff24)
        let source=try SourceAudioFile(url),edit=d.cropped(200..<32000),destination=cache.folder.appendingPathComponent("convert.wav")
        var trashCalled=false
        let result=try FileAudioWriter.convertToWAV(edit,source:source) {original in
            XCTAssertEqual(try cache.read(destination).frames,31800)
            XCTAssertEqual(try SourceEncoding(inspecting:destination).bits,24)
            let trash=cache.folder.appendingPathComponent("test-trash.aiff")
            try FileManager.default.moveItem(at:original,to:trash);trashCalled=true;return trash
        }
        XCTAssertEqual(trashCalled,true);XCTAssertNil(result.warning);XCTAssertEqual(result.file.url,destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path));XCTAssertEqual(try cache.read(destination).frames,31800)
    }
    func testConversionCollisionAndTrashFailure() throws {
        let d=try signal(),url=cache.folder.appendingPathComponent("same.wav")
        try FileAudioWriter.write(d,to:url,encoding:.wav(rate:d.rate,channels:2,bits:16))
        let source=try SourceAudioFile(url),before=try Data(contentsOf:url)
        let occupied=cache.folder.appendingPathComponent("same-转换.wav"),sentinel=Data("existing WAV must stay".utf8);try sentinel.write(to:occupied)
        let result=try FileAudioWriter.convertToWAV(d,source:source) {_ in throw CocoaError(.fileWriteNoPermission)}
        XCTAssertEqual(result.file.url.lastPathComponent,"same-转换-2.wav");XCTAssertEqual(result.warning != nil,true)
        XCTAssertEqual(try Data(contentsOf:url),before);XCTAssertEqual(try Data(contentsOf:occupied),sentinel)
        XCTAssertEqual(try cache.read(result.file.url).frames,d.frames)
    }
}
