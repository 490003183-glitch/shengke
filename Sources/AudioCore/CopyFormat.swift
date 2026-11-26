import Foundation

public enum CopyFormat:CaseIterable {
    case source,wav16,wav24,wavFloat,aiff24,flac24,alac24,aac,mp3
    public func isAvailable(rate:Double,source:SourceEncoding?,frames:Int=Int.max)->Bool {
        if self == .source {return source != nil}
        if self == .flac24 {return frames>=4608}
        // The native readback decoder rejects the current 32 kHz LAME output.
        if self == .mp3 {return [8000.0,11025,12000,16000,22050,24000,44100,48000].contains(rate)}
        if self == .aac {return [32000.0,44100,48000].contains(rate)}
        return true
    }
    public func encoding(rate:Double,channels:Int,source:SourceEncoding?)->SourceEncoding {
        switch self {
        case .source:return source ?? .wav(rate:rate,channels:channels)
        case .wav16:return .wav(rate:rate,channels:channels,bits:16)
        case .wav24:return .wav(rate:rate,channels:channels)
        case .wavFloat:return .wav(rate:rate,channels:channels,bits:32,isFloat:true)
        case .aiff24:return .aiff(rate:rate,channels:channels)
        case .flac24:return .compressed(rate:rate,channels:channels,lossless:true,flac:true)
        case .alac24:return .compressed(rate:rate,channels:channels,lossless:true)
        case .aac:return .compressed(rate:rate,channels:channels,lossless:false)
        case .mp3:return .mp3(rate:rate,channels:channels,bitRate:rate>=32000 ? 192000 : rate>=16000 ? 96000 : 48000)
        }
    }
    public func title(rate:Double,channels:Int,source:SourceEncoding?)->String {
        switch self {
        case .source:return "与源文件相同（\(source?.description ?? "WAV 24-bit")）"
        case .wav16:return "WAV · 16-bit"
        case .wav24:return "WAV · 24-bit"
        case .wavFloat:return "WAV · 32-bit float"
        case .aiff24:return "AIFF · 24-bit"
        case .flac24:return "FLAC · 24-bit 无损"
        case .alac24:return "Apple Lossless · M4A 24-bit 无损"
        case .aac:return "AAC · M4A \((rate<44100 ? 96 : 128)*channels) kbps"
        case .mp3:return "MP3 · \(rate>=32000 ? 192 : rate>=16000 ? 96 : 48) kbps"
        }
    }
}
