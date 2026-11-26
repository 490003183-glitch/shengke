import Foundation
import AVFoundation
import Darwin

public enum AudioError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}

public final class AudioCache {
    public let folder: URL
    public init(base: URL = FileManager.default.temporaryDirectory) throws {
        folder = base.appendingPathComponent("WaveStudio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: folder) }
    public func makeAsset(rate: Double, channels: Int, frames: Int,
                          samples: (Int, Int) throws -> [[Float]]) throws -> AudioAsset {
        guard rate.isFinite, rate > 0, (1...2).contains(channels), frames >= 0 else { throw AudioError.invalid("音频参数无效（首版支持单声道和立体声）。") }
        let url = folder.appendingPathComponent(UUID().uuidString + ".pcm")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        do {
            for start in stride(from: 0, to: frames, by: 16384) {
                let count = min(16384, frames - start)
                let block = try samples(start, count)
                guard block.count == channels, block.allSatisfy({ $0.count == count }) else { throw AudioError.invalid("音频数据长度不一致。") }
                var interleaved = [Float](repeating: 0, count: count * channels)
                for c in 0..<channels { for f in 0..<count {
                    let value = block[c][f]
                    interleaved[f * channels + c] = value.isFinite ? value : 0
                } }
                try interleaved.withUnsafeBytes { try handle.write(contentsOf: $0) }
            }
            try handle.close()
            return try AudioAsset(url: url, cache: self, rate: rate, channels: channels, frames: frames)
        } catch {
            try? handle.close(); try? FileManager.default.removeItem(at: url); throw error
        }
    }
    public func read(_ url: URL) throws -> AudioDocument {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard (1...2).contains(Int(format.channelCount)) else { throw AudioError.invalid("首版支持单声道和立体声，当前文件有 \(format.channelCount) 个声道。") }
        guard file.length > 0, file.length < Int64(Int.max / 16) else { throw AudioError.invalid("音频文件为空或长度无效。") }
        let asset = try makeAsset(rate: format.sampleRate, channels: Int(format.channelCount), frames: Int(file.length)) { _, count in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { throw AudioError.invalid("无法分配音频缓冲区。") }
            try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
            guard Int(buffer.frameLength) == count, let data = buffer.floatChannelData else { throw AudioError.invalid("音频数据不完整，已取消打开。") }
            return (0..<Int(format.channelCount)).map { Array(UnsafeBufferPointer(start: data[$0], count: count)) }
        }
        return AudioDocument(rate: format.sampleRate, channels: Int(format.channelCount), pieces: [Piece(asset: asset, offset: 0, count: asset.frames)])
    }
}

public struct Peak {
    public var low: Float
    public var high: Float
    public init(_ low: Float = 0, _ high: Float = 0) { self.low = low; self.high = high }
    public mutating func include(_ other: Peak) { low = min(low, other.low); high = max(high, other.high) }
}

public final class AudioAsset {
    public let url: URL
    private let cache: AudioCache
    private let mapping: NSData
    private let pointer: UnsafePointer<Float>
    public let rate: Double
    public let channels: Int
    public let frames: Int
    private var peaks: [[[Peak]]] = [] // level, channel, block; base 256 frames
    fileprivate init(url: URL, cache: AudioCache, rate: Double, channels: Int, frames: Int) throws {
        self.url = url; self.cache = cache; self.rate = rate; self.channels = channels; self.frames = frames
        mapping = try NSData(contentsOf: url, options: .mappedIfSafe)
        pointer = mapping.bytes.assumingMemoryBound(to: Float.self)
        guard mapping.length == frames * channels * 4 else { throw AudioError.invalid("缓存长度异常。") }
        if frames > 0 {
            var base = [[Peak]](repeating: [], count: channels)
            for c in 0..<channels {
                for start in stride(from: 0, to: frames, by: 256) {
                    var p = Peak()
                    for f in start..<min(start+256, frames) { let x = pointer[f*channels+c]; p.low = min(p.low,x); p.high = max(p.high,x) }
                    base[c].append(p)
                }
            }
            peaks.append(base)
            while peaks.last![0].count > 1 {
                let prev = peaks.last!
                var next = [[Peak]](repeating: [], count: channels)
                for c in 0..<channels { for i in stride(from: 0, to: prev[c].count, by: 4) {
                    var p = Peak(); for j in i..<min(i+4,prev[c].count) { p.include(prev[c][j]) }; next[c].append(p)
                } }
                peaks.append(next)
            }
        }
    }
    public func sample(_ frame: Int, _ channel: Int) -> Float { pointer[frame * channels + channel] }
    public func peak(_ range: Range<Int>, channel: Int) -> Peak {
        var p = Peak(); var i = max(0,range.lowerBound); let end = min(frames,range.upperBound)
        while i < end {
            var size = 256; var level = 0
            if i % size == 0 && i+size <= end {
                while level+1 < peaks.count && i % (size*4) == 0 && i+size*4 <= end { size *= 4; level += 1 }
                p.include(peaks[level][channel][i/size]); i += size
            } else { let x = sample(i,channel); p.low = min(p.low,x); p.high = max(p.high,x); i += 1 }
        }
        return p
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

public struct Piece {
    public let asset: AudioAsset
    public var offset: Int
    public var count: Int
    public init(asset: AudioAsset, offset: Int, count: Int) { self.asset = asset; self.offset = offset; self.count = count }
}
public struct AudioMarker: Identifiable, Equatable, Codable {
    public let id: UUID
    public var frame: Int
    public var name: String
    public init(frame: Int, name: String, id: UUID = UUID()) { self.id = id; self.frame = frame; self.name = name }
}
public struct AudioDocument {
    public var rate: Double
    public var channels: Int
    public var pieces: [Piece]
    public var markers: [AudioMarker] = []
    public var revision = UUID()
    public var frames: Int { pieces.reduce(0) { $0 + $1.count } }
    public var duration: Double { Double(frames) / rate }
    public init(rate: Double = 48000, channels: Int = 2, pieces: [Piece] = []) { self.rate = rate; self.channels = channels; self.pieces = pieces }
    public func sliced(_ range: Range<Int>) -> [Piece] {
        var position = 0; var out: [Piece] = []
        for piece in pieces {
            let start = max(position, range.lowerBound), end = min(position+piece.count,range.upperBound)
            if start < end { out.append(Piece(asset: piece.asset, offset: piece.offset+start-position, count: end-start)) }
            position += piece.count
            if position >= range.upperBound { break }
        }
        return out
    }
    public func samples(_ range: Range<Int>) -> [[Float]] {
        let slices = sliced(range)
        var out = [[Float]](repeating: [], count: channels)
        for c in 0..<channels {
            out[c].reserveCapacity(range.count)
            for p in slices { for f in p.offset..<p.offset+p.count { out[c].append(p.asset.sample(f,c)) } }
        }
        return out
    }
    public func peak(_ range: Range<Int>, channel: Int) -> Peak {
        var result = Peak()
        for p in sliced(range) { result.include(p.asset.peak(p.offset..<p.offset+p.count,channel: channel)) }
        return result
    }
    public func replacing(_ range: Range<Int>, with inserted: [Piece]) -> AudioDocument {
        precondition(range.lowerBound >= 0 && range.upperBound <= frames)
        var next = self
        next.pieces = sliced(0..<range.lowerBound) + inserted.filter { $0.count > 0 } + sliced(range.upperBound..<frames)
        let added = inserted.reduce(0) { $0+$1.count }, delta = added-range.count
        next.markers = markers.compactMap { m in
            var m = m
            if range.isEmpty { if m.frame >= range.lowerBound { m.frame += added } }
            else if m.frame >= range.upperBound { m.frame += delta }
            else if m.frame > range.lowerBound { return nil }
            return m
        }
        next.revision = UUID(); return next
    }
    public func cropped(_ range: Range<Int>) -> AudioDocument {
        var next = self; next.pieces = sliced(range)
        next.markers = markers.filter { $0.frame >= range.lowerBound && $0.frame <= range.upperBound }.map { var m = $0; m.frame -= range.lowerBound; return m }
        next.revision = UUID(); return next
    }
    public func transformed(_ range: Range<Int>, effect: Effect, cache: AudioCache) throws -> AudioDocument {
        guard !range.isEmpty else { return self }
        var gain: Float = 1
        if case .gain(let db) = effect {
            guard db.isFinite, (-96...48).contains(db) else { throw AudioError.invalid("增益请输入 -96 到 +48 dB。") }
            gain = Float(pow(10,db/20))
        }
        if case .normalize(let db) = effect {
            guard db.isFinite, (-96...0).contains(db) else { throw AudioError.invalid("归一化目标应为 -96 到 0 dBFS。") }
            let maximum = (0..<channels).map { c -> Float in let p=peak(range,channel:c); return max(abs(p.low),abs(p.high)) }.max() ?? 0
            gain = maximum > 0 ? Float(pow(10,db/20))/maximum : 1
        }
        let asset = try cache.makeAsset(rate: rate, channels: channels, frames: range.count) { start,count in
            let reverse: Bool; if case .reverse = effect { reverse = true } else { reverse = false }
            let source = reverse ? (range.upperBound-start-count)..<(range.upperBound-start) : (range.lowerBound+start)..<(range.lowerBound+start+count)
            var block = samples(source)
            for c in 0..<channels {
                if reverse { block[c].reverse() }
                for i in 0..<count {
                    let t = range.count > 1 ? Float(start+i)/Float(range.count-1) : 1
                    switch effect {
                    case .gain, .normalize: block[c][i] *= gain
                    case .fadeIn: block[c][i] *= t
                    case .fadeOut: block[c][i] *= 1-t
                    case .silence: block[c][i] = 0
                    case .invert: block[c][i] = -block[c][i]
                    case .reverse: break
                    }
                }
            }
            return block
        }
        // Effects preserve positions, including markers within the selection.
        var next = replacing(range, with: [Piece(asset:asset,offset:0,count:asset.frames)])
        next.markers = markers; return next
    }
}
public enum Effect { case gain(Double), normalize(Double), fadeIn, fadeOut, silence, reverse, invert }
public struct EditorSnapshot {
    public var audio: AudioDocument
    public var selection: Range<Int>
    public init(audio: AudioDocument = AudioDocument(), selection: Range<Int> = 0..<0) { self.audio=audio; self.selection=selection }
}
public final class EditHistory {
    public private(set) var state: EditorSnapshot
    private var undoEntries: [(String,EditorSnapshot)] = []
    private var redoEntries: [(String,EditorSnapshot)] = []
    public var undoName: String? { undoEntries.last?.0 }
    public var redoName: String? { redoEntries.last?.0 }
    public init(_ state: EditorSnapshot = EditorSnapshot()) { self.state=state }
    public func select(_ range: Range<Int>) { state.selection=range }
    public func commit(_ next: EditorSnapshot, name: String) { undoEntries.append((name,state)); redoEntries.removeAll(); state=next }
    public func undo() { guard let (name,prev)=undoEntries.popLast() else { return }; redoEntries.append((name,state)); state=prev }
    public func redo() { guard let (name,next)=redoEntries.popLast() else { return }; undoEntries.append((name,state)); state=next }
}

public enum ExportFormat: String, CaseIterable {
    case wav16 = "WAV · 16-bit", wav24 = "WAV · 24-bit", wavFloat = "WAV · 32-bit float", aiff24 = "AIFF · 24-bit", aac = "M4A · AAC 256 kbps"
    public var ext: String { switch self { case .aiff24: return "aiff"; case .aac: return "m4a"; default: return "wav" } }
    public func settings(rate: Double, channels: Int) -> [String: Any] {
        if self == .aac { return [AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:rate,AVNumberOfChannelsKey:channels,AVEncoderBitRateKey:256000] }
        let bits = self == .wav16 ? 16 : self == .wavFloat ? 32 : 24
        return [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:rate,AVNumberOfChannelsKey:channels,AVLinearPCMBitDepthKey:bits,AVLinearPCMIsFloatKey:self == .wavFloat,AVLinearPCMIsBigEndianKey:self == .aiff24,AVLinearPCMIsNonInterleaved:false]
    }
}
public enum AudioExporter {
    public static func write(_ audio: AudioDocument, range: Range<Int>, to destination: URL, format: ExportFormat) throws {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= audio.frames else { throw AudioError.invalid("请选择需要导出的音频。") }
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".wavestudio-\(UUID().uuidString).\(format.ext)")
        defer { try? FileManager.default.removeItem(at: temp) }
        // The file must be closed before it is atomically renamed (AAC finalizes on deinit).
        try render(audio,range:range,to:temp,format:format)
        let check = try AVAudioFile(forReading:temp)
        guard check.length > 0, Int(check.processingFormat.channelCount) == audio.channels else { throw AudioError.invalid("导出文件回读检查失败。") }
        let result = temp.withUnsafeFileSystemRepresentation { src in destination.withUnsafeFileSystemRepresentation { dst in Darwin.rename(src!,dst!) } }
        guard result == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
    }
    private static func render(_ audio: AudioDocument, range: Range<Int>, to url: URL, format: ExportFormat) throws {
        let file = try AVAudioFile(forWriting:url,settings:format.settings(rate:audio.rate,channels:audio.channels),commonFormat:.pcmFormatFloat32,interleaved:false)
        for start in stride(from:range.lowerBound,to:range.upperBound,by:16384) {
            let end=min(start+16384,range.upperBound)
            let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(end-start))!
            buffer.frameLength=buffer.frameCapacity
            let block=audio.samples(start..<end)
            for c in 0..<audio.channels { block[c].withUnsafeBufferPointer { p in buffer.floatChannelData![c].update(from:p.baseAddress!,count:block[c].count) } }
            try file.write(from:buffer)
        }
    }
}
