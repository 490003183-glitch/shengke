import Foundation
import AVFoundation
import AudioToolbox
import Darwin
import CLame

public struct FileSnapshot:Equatable {
    let size:UInt64
    let modified:Date
    let inode:UInt64
    let device:UInt64
    public init(_ url:URL) throws {
        let a=try FileManager.default.attributesOfItem(atPath:url.path)
        guard a[.type] as? FileAttributeType == .typeRegular else {throw AudioError.invalid("源文件不是普通音频文件。")}
        size=(a[.size] as? NSNumber)?.uint64Value ?? 0
        modified=a[.modificationDate] as? Date ?? .distantPast
        inode=(a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        device=(a[.systemNumber] as? NSNumber)?.uint64Value ?? 0
    }
}
public struct SourceEncoding {
    public let container:AudioFileTypeID
    public let codec:AudioFormatID
    public let rate:Double
    public let channels:Int
    public let bits:Int
    public let isFloat:Bool
    public let bitRate:Int
    public let variableMP3:Bool
    public let settings:[String:Any]
    public var fileExtension:String {
        switch container {
        case kAudioFileWAVEType:return "wav"
        case kAudioFileAIFFType:return "aiff"
        case kAudioFileAIFCType:return "aifc"
        case kAudioFileCAFType:return "caf"
        case kAudioFileM4AType:return "m4a"
        case kAudioFileM4BType:return "m4b"
        case kAudioFileMPEG4Type:return "mp4"
        case kAudioFileMP3Type:return "mp3"
        case kAudioFileAAC_ADTSType:return "aac"
        case kAudioFileFLACType:return "flac"
        default:return "caf"
        }
    }
    public var description:String {
        let known:[AudioFormatID:String]=[kAudioFormatLinearPCM:"PCM",kAudioFormatMPEGLayer3:"MP3",kAudioFormatAppleLossless:"ALAC",kAudioFormatFLAC:"FLAC",kAudioFormatMPEG4AAC:"AAC",kAudioFormatMPEG4AAC_HE:"HE-AAC",kAudioFormatMPEG4AAC_HE_V2:"HE-AAC v2"]
        let name=known[codec] ?? String(bytes:[UInt8((codec>>24)&255),UInt8((codec>>16)&255),UInt8((codec>>8)&255),UInt8(codec&255)],encoding:.ascii) ?? "未知编码"
        let detail=codec == kAudioFormatLinearPCM ? "\(bits)-bit\(isFloat ? " float" : "")" : bitRate>0 ? "\(bitRate/1000) kbps\(variableMP3 ? " VBR" : "")" : "\(bits)-bit"
        return "\(fileExtension.uppercased()) · \(name) \(detail)"
    }
    public init(inspecting url:URL) throws {
        let file=try AVAudioFile(forReading:url)
        var handle:AudioFileID?
        let status=AudioFileOpenURL(url as CFURL,.readPermission,0,&handle)
        guard status==noErr,let handle=handle else {throw AudioError.invalid("无法读取源文件编码（\(status)）。")}
        defer {AudioFileClose(handle)}
        var asbd=AudioStreamBasicDescription(),formatSize=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(handle,kAudioFilePropertyDataFormat,&formatSize,&asbd)==noErr else {throw AudioError.invalid("无法读取原始音频编码参数。")}
        func uint(_ property:AudioFilePropertyID)->UInt32 {
            var value:UInt32=0,size=UInt32(MemoryLayout<UInt32>.size)
            return AudioFileGetProperty(handle,property,&size,&value)==noErr ? value : 0
        }
        container=uint(kAudioFilePropertyFileFormat);codec=asbd.mFormatID;rate=asbd.mSampleRate;channels=Int(asbd.mChannelsPerFrame)
        bits=Int(asbd.mBitsPerChannel>0 ? asbd.mBitsPerChannel : uint(kAudioFilePropertySourceBitDepth))
        isFloat=codec==kAudioFormatLinearPCM && asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        bitRate=Int(uint(kAudioFilePropertyBitRate))
        variableMP3=codec==kAudioFormatMPEGLayer3 && Self.hasXingHeader(url)
        var options=file.fileFormat.settings
        if codec==kAudioFormatLinearPCM {
            options=[AVFormatIDKey:codec,AVSampleRateKey:rate,AVNumberOfChannelsKey:channels,AVLinearPCMBitDepthKey:bits,AVLinearPCMIsFloatKey:isFloat,AVLinearPCMIsBigEndianKey:asbd.mFormatFlags & kAudioFormatFlagIsBigEndian != 0,AVLinearPCMIsNonInterleaved:false]
        }
        else if codec==kAudioFormatAppleLossless || codec==kAudioFormatFLAC {if bits>0 {options[AVEncoderBitDepthHintKey]=bits}}
        else if codec != kAudioFormatMPEGLayer3,bitRate>0 {options[AVEncoderBitRateKey]=bitRate}
        settings=options
    }
    public static func wav(rate:Double,channels:Int,bits:Int=24,isFloat:Bool=false)->SourceEncoding {
        SourceEncoding(container:kAudioFileWAVEType,codec:kAudioFormatLinearPCM,rate:rate,channels:channels,bits:bits,isFloat:isFloat,bitRate:Int(rate)*channels*bits,variableMP3:false,settings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:rate,AVNumberOfChannelsKey:channels,AVLinearPCMBitDepthKey:bits,AVLinearPCMIsFloatKey:isFloat,AVLinearPCMIsBigEndianKey:false,AVLinearPCMIsNonInterleaved:false])
    }
    public static func mp3(rate:Double,channels:Int,bitRate:Int=192000,variable:Bool=false)->SourceEncoding {
        SourceEncoding(container:kAudioFileMP3Type,codec:kAudioFormatMPEGLayer3,rate:rate,channels:channels,bits:0,isFloat:false,bitRate:bitRate,variableMP3:variable,settings:[:])
    }
    private init(container:AudioFileTypeID,codec:AudioFormatID,rate:Double,channels:Int,bits:Int,isFloat:Bool,bitRate:Int,variableMP3:Bool,settings:[String:Any]) {
        self.container=container;self.codec=codec;self.rate=rate;self.channels=channels;self.bits=bits;self.isFloat=isFloat;self.bitRate=bitRate;self.variableMP3=variableMP3;self.settings=settings
    }
    private static func hasXingHeader(_ url:URL)->Bool {
        guard let file=try? FileHandle(forReadingFrom:url) else{return false};defer{try? file.close()}
        guard let header=try? file.read(upToCount:10),header.count==10 else{return false}
        var offset:UInt64=0
        if header.prefix(3)==Data("ID3".utf8) {offset=UInt64(10+(Int(header[6]&127)<<21)+(Int(header[7]&127)<<14)+(Int(header[8]&127)<<7)+Int(header[9]&127))}
        try? file.seek(toOffset:offset)
        guard let data=try? file.read(upToCount:1024) else{return false}
        return data.range(of:Data("Xing".utf8)) != nil
    }
    func matches(_ other:SourceEncoding)->Bool {
        container==other.container && codec==other.codec && rate==other.rate && channels==other.channels && (codec != kAudioFormatLinearPCM || (bits==other.bits && isFloat==other.isFloat))
    }
}
public struct SourceAudioFile {
    public let url:URL
    public let encoding:SourceEncoding
    public let snapshot:FileSnapshot
    public init(_ url:URL) throws {
        self.url=url.resolvingSymlinksInPath().standardizedFileURL
        snapshot=try FileSnapshot(self.url);encoding=try SourceEncoding(inspecting:self.url)
        try assertUnchanged()
    }
    public func assertUnchanged() throws {
        guard try FileSnapshot(url)==snapshot else {throw AudioError.invalid("源文件在外部已被修改或替换，未覆盖也未删除。请保存为副本。")}
    }
}
public struct WAVConversionResult {
    public let file:SourceAudioFile
    public let trashedSource:URL?
    public let warning:String?
}
public enum FileAudioWriter {
    public static func write(_ audio:AudioDocument,to destination:URL,encoding:SourceEncoding,overwriting source:SourceAudioFile?=nil,exclusive:Bool=false) throws {
        guard audio.frames>0,audio.rate==encoding.rate,audio.channels==encoding.channels else {throw AudioError.invalid("音频为空，或采样率/声道与源编码不一致。")}
        if let source=source {
            guard destination.resolvingSymlinksInPath().standardizedFileURL==source.url else {throw AudioError.invalid("覆盖目标与源文件不一致。")}
            try source.assertUnchanged()
        }
        if FileManager.default.fileExists(atPath:destination.path) {_=try FileSnapshot(destination)}
        let temp=destination.deletingLastPathComponent().appendingPathComponent(".sound-edit-\(UUID().uuidString).\(encoding.fileExtension)")
        defer {try? FileManager.default.removeItem(at:temp)}
        if encoding.codec==kAudioFormatMPEGLayer3 {try renderMP3(audio,to:temp,encoding:encoding)}
        else {try renderNative(audio,to:temp,encoding:encoding)}
        let profile=try SourceEncoding(inspecting:temp),check=try AVAudioFile(forReading:temp)
        let lossless=[kAudioFormatLinearPCM,kAudioFormatAppleLossless,kAudioFormatFLAC].contains(encoding.codec)
        let tolerance=lossless ? 0 : max(2304,Int(audio.rate*0.075))
        guard encoding.matches(profile),abs(Int(check.length)-audio.frames)<=tolerance else {throw AudioError.invalid("保存校验失败：预期 \(encoding.description) / \(audio.frames) 帧，实际 \(profile.description) / \(check.length) 帧，原文件保持不变。")}
        // Also decode through the final frame, so truncated payloads cannot pass on header length alone.
        let capacity:AVAudioFrameCount=16384
        let buffer=AVAudioPCMBuffer(pcmFormat:check.processingFormat,frameCapacity:capacity)!
        var read:Int64=0
        while read<check.length {try check.read(into:buffer,frameCount:AVAudioFrameCount(min(Int64(capacity),check.length-read)));guard buffer.frameLength>0 else {throw AudioError.invalid("保存文件回读不完整。")};read += Int64(buffer.frameLength)}
        try source?.assertUnchanged()
        if FileManager.default.fileExists(atPath:destination.path),let mode=try FileManager.default.attributesOfItem(atPath:destination.path)[.posixPermissions] {try FileManager.default.setAttributes([.posixPermissions:mode],ofItemAtPath:temp.path)}
        let result=temp.withUnsafeFileSystemRepresentation {src in destination.withUnsafeFileSystemRepresentation {dst in exclusive ? renamex_np(src!,dst!,UInt32(RENAME_EXCL)) : Darwin.rename(src!,dst!)}}
        guard result==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
    }
    public static func copy(_ audio:AudioDocument,source:SourceAudioFile,to destination:URL) throws {
        guard destination.resolvingSymlinksInPath().standardizedFileURL != source.url else {throw AudioError.invalid("副本不能与源文件使用同一个路径。请另取文件名。")}
        try write(audio,to:destination,encoding:source.encoding)
    }
    public static func convertToWAV(_ audio:AudioDocument,source:SourceAudioFile,trash:(URL)throws->URL? = moveToTrash) throws -> WAVConversionResult {
        try source.assertUnchanged()
        let base=source.url.deletingPathExtension()
        var destination=base.appendingPathExtension("wav"),index=1
        while FileManager.default.fileExists(atPath:destination.path) {
            destination=base.deletingLastPathComponent().appendingPathComponent(base.lastPathComponent+"-转换\(index==1 ? "" : "-\(index)").wav");index += 1
        }
        try write(audio,to:destination,encoding:.wav(rate:audio.rate,channels:audio.channels),exclusive:true)
        let written=try SourceAudioFile(destination)
        do {
            try source.assertUnchanged()
            return WAVConversionResult(file:written,trashedSource:try trash(source.url),warning:nil)
        } catch {
            return WAVConversionResult(file:written,trashedSource:nil,warning:"WAV 已保存到 \(destination.path)，但源文件未删除：\(error.localizedDescription)")
        }
    }
    public static func moveToTrash(_ url:URL) throws -> URL? {
        var result:NSURL?;try FileManager.default.trashItem(at:url,resultingItemURL:&result);return result as URL?
    }
    private static func renderNative(_ audio:AudioDocument,to url:URL,encoding:SourceEncoding) throws {
        if encoding.codec==kAudioFormatLinearPCM {try renderPCM(audio,to:url,encoding:encoding);return}
        let file=try AVAudioFile(forWriting:url,settings:encoding.settings,commonFormat:.pcmFormatFloat32,interleaved:false)
        for start in stride(from:0,to:audio.frames,by:16384) {
            let end=min(start+16384,audio.frames),samples=audio.samples(start..<end)
            let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(end-start))!;buffer.frameLength=buffer.frameCapacity
            for c in 0..<audio.channels {samples[c].withUnsafeBufferPointer {buffer.floatChannelData![c].update(from:$0.baseAddress!,count:end-start)}}
            try file.write(from:buffer)
        }
    }
    private static func renderPCM(_ audio:AudioDocument,to url:URL,encoding:SourceEncoding) throws {
        // AVAudioFile can substitute AIFC for AIFF or Float32 for Float64.
        // Specify the actual container and storage format to the file converter.
        let bigEndian=(encoding.settings[AVLinearPCMIsBigEndianKey] as? Bool) ?? false
        let signed=encoding.bits != 8 || encoding.container != kAudioFileWAVEType
        let bytes=UInt32(audio.channels*((encoding.bits+7)/8))
        var format=AudioStreamBasicDescription(mSampleRate:audio.rate,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagIsPacked | (encoding.isFloat ? kAudioFormatFlagIsFloat : signed ? kAudioFormatFlagIsSignedInteger : 0) | (bigEndian ? kAudioFormatFlagIsBigEndian : 0),mBytesPerPacket:bytes,mFramesPerPacket:1,mBytesPerFrame:bytes,mChannelsPerFrame:UInt32(audio.channels),mBitsPerChannel:UInt32(encoding.bits),mReserved:0)
        var file:ExtAudioFileRef?
        let status=ExtAudioFileCreateWithURL(url as CFURL,encoding.container,&format,nil,AudioFileFlags.eraseFile.rawValue,&file)
        guard status==noErr,let file=file else {throw AudioError.invalid("无法创建源格式音频（\(status)）。")};defer{ExtAudioFileDispose(file)}
        let input=AVAudioFormat(standardFormatWithSampleRate:audio.rate,channels:AVAudioChannelCount(audio.channels))!
        var client=input.streamDescription.pointee
        let configured=ExtAudioFileSetProperty(file,kExtAudioFileProperty_ClientDataFormat,UInt32(MemoryLayout<AudioStreamBasicDescription>.size),&client)
        guard configured==noErr else {throw AudioError.invalid("无法设置音频转换格式（\(configured)）。")}
        for start in stride(from:0,to:audio.frames,by:16384) {
            let end=min(start+16384,audio.frames),samples=audio.samples(start..<end)
            let buffer=AVAudioPCMBuffer(pcmFormat:input,frameCapacity:AVAudioFrameCount(end-start))!;buffer.frameLength=buffer.frameCapacity
            for c in 0..<audio.channels {samples[c].withUnsafeBufferPointer {buffer.floatChannelData![c].update(from:$0.baseAddress!,count:end-start)}}
            let code=ExtAudioFileWrite(file,buffer.frameLength,buffer.audioBufferList)
            guard code==noErr else {throw AudioError.invalid("源格式音频写入失败（\(code)）。")}
        }
    }
    private static func renderMP3(_ audio:AudioDocument,to url:URL,encoding:SourceEncoding) throws {
        guard let encoder=lame_init() else {throw AudioError.invalid("无法启动 MP3 编码器。")};defer {lame_close(encoder)}
        lame_set_in_samplerate(encoder,Int32(audio.rate));lame_set_out_samplerate(encoder,Int32(audio.rate));lame_set_num_channels(encoder,Int32(audio.channels))
        lame_set_num_samples(encoder,UInt(audio.frames));lame_set_quality(encoder,2);lame_set_write_id3tag_automatic(encoder,0)
        let supported=[8,16,24,32,40,48,56,64,80,96,112,128,144,160,192,224,256,320]
        let kbps=supported.min {abs($0-encoding.bitRate/1000)<abs($1-encoding.bitRate/1000)} ?? 192
        if encoding.variableMP3 {lame_set_VBR(encoder,vbr_abr);lame_set_VBR_mean_bitrate_kbps(encoder,Int32(kbps))}
        else {lame_set_brate(encoder,Int32(kbps))}
        guard lame_init_params(encoder)>=0 else {throw AudioError.invalid("MP3 源编码参数不受支持。")}
        guard FileManager.default.createFile(atPath:url.path,contents:nil) else {throw AudioError.invalid("无法创建保存文件。")}
        let file=try FileHandle(forWritingTo:url);defer{try? file.close()}
        var bytes=[UInt8](repeating:0,count:32768)
        func append(_ count:Int32) throws {guard count>=0 else {throw AudioError.invalid("MP3 编码失败（\(count)）。")};try file.write(contentsOf:Data(bytes.prefix(Int(count))))}
        for start in stride(from:0,to:audio.frames,by:16384) {
            let end=min(audio.frames,start+16384),samples=audio.samples(start..<end)
            let count=samples[0].withUnsafeBufferPointer {left in samples[audio.channels-1].withUnsafeBufferPointer {right in lame_encode_buffer_ieee_float(encoder,left.baseAddress!,right.baseAddress!,Int32(end-start),&bytes,Int32(bytes.count))}}
            try append(count)
        }
        try append(lame_encode_flush(encoder,&bytes,Int32(bytes.count)))
        let tag=lame_get_lametag_frame(encoder,&bytes,bytes.count)
        guard tag<=bytes.count else {throw AudioError.invalid("MP3 时长标记写入失败。")}
        if tag>0 {try file.seek(toOffset:0);try file.write(contentsOf:Data(bytes.prefix(tag)))}
        try file.synchronize()
    }
}
