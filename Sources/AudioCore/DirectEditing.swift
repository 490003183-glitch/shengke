import Foundation
import AVFoundation

/// Blend the unchanged and gain-adjusted copies of the same (correlated) signal.
/// Complementary raised-cosine weights avoid the +3 dB bulge of equal-power mixing.
public struct SelectionGain:Equatable {
    public let range:Range<Int>
    public let decibels:Double
    public let transitionSeconds:Double
    public init(range:Range<Int>,decibels:Double,transitionSeconds:Double=0.015) {
        self.range=range;self.decibels=decibels;self.transitionSeconds=transitionSeconds
    }
    public func multiplier(at frame:Int,rate:Double)->Float {
        guard range.contains(frame),!range.isEmpty else{return 1}
        let edge=min(max(1,Int((rate*transitionSeconds).rounded())),max(1,(range.count-1)/2))
        let distance=min(frame-range.lowerBound,range.upperBound-1-frame)
        let phase=min(1,Double(distance)/Double(edge))
        let blend=0.5-0.5*cos(.pi*phase)
        return Float(1+(pow(10,decibels/20)-1)*blend)
    }
    public func applied(to audio:AudioDocument,cache:AudioCache) throws -> AudioDocument {
        guard range.lowerBound>=0,range.upperBound<=audio.frames,!range.isEmpty,decibels.isFinite,(-60...24).contains(decibels),transitionSeconds.isFinite,transitionSeconds>0 else {throw AudioError.invalid("选区音量参数无效。")}
        if abs(decibels)<0.00001 {return audio}
        let asset=try cache.makeAsset(rate:audio.rate,channels:audio.channels,frames:range.count) {start,count in
            var block=audio.samples((range.lowerBound+start)..<(range.lowerBound+start+count))
            for i in 0..<count {let gain=multiplier(at:range.lowerBound+start+i,rate:audio.rate);for c in 0..<audio.channels {block[c][i] *= gain}}
            return block
        }
        var next=audio.replacing(range,with:[Piece(asset:asset,offset:0,count:range.count)])
        next.markers=audio.markers;return next
    }
}

public enum ClipExporter {
    public static let rate=48000.0
    public static let fadeFrames=720
    public static func fade(at frame:Int,frames:Int)->Float {
        guard frames>1 else{return 0}
        let length=min(fadeFrames,max(1,(frames-1)/2))
        let distance=min(frame,frames-1-frame)
        return Float(0.5-0.5*cos(.pi*min(1,Double(distance)/Double(length))))
    }
    public static func render(_ audio:AudioDocument,range:Range<Int>,gain:SelectionGain?=nil,cache:AudioCache) throws -> AudioDocument {
        guard !range.isEmpty,range.lowerBound>=0,range.upperBound<=audio.frames,(1...2).contains(audio.channels) else {throw AudioError.invalid("请先选择要拖出的片段。")}
        let count=max(1,Int((Double(range.count)/audio.rate*rate).rounded()))
        let input=AVAudioFormat(standardFormatWithSampleRate:audio.rate,channels:2)!
        let output=AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!
        guard let converter=AVAudioConverter(from:input,to:output) else {throw AudioError.invalid("无法将选区转换为 48 kHz 立体声。")}
        converter.sampleRateConverterQuality=127
        var cursor=range.lowerBound
        // A fractional final destination frame needs zero-extended input for the
        // resampler; the output is still trimmed to the rounded selection duration.
        let inputEnd=range.upperBound+max(512,Int(audio.rate/rate*512))
        let asset=try cache.makeAsset(rate:rate,channels:2,frames:count) {start,length in
            var result=[[Float]](repeating:[],count:2)
            while result[0].count<length {
                let remaining=length-result[0].count
                let buffer=AVAudioPCMBuffer(pcmFormat:output,frameCapacity:AVAudioFrameCount(remaining))!
                var error:NSError?
                let status=converter.convert(to:buffer,error:&error) {requested,state in
                    guard cursor<inputEnd else {state.pointee = .endOfStream;return nil}
                    let n=min(Int(requested),inputEnd-cursor)
                    let real=max(0,min(n,range.upperBound-cursor))
                    let data=real>0 ? audio.samples(cursor..<cursor+real) : [[Float]](repeating:[],count:audio.channels)
                    let chunk=AVAudioPCMBuffer(pcmFormat:input,frameCapacity:AVAudioFrameCount(n))!;chunk.frameLength=chunk.frameCapacity
                    for c in 0..<2 {for i in 0..<n {chunk.floatChannelData![c][i]=i<real ? data[min(c,audio.channels-1)][i]*(gain?.multiplier(at:cursor+i,rate:audio.rate) ?? 1) : 0}}
                    cursor += n;state.pointee = .haveData;return chunk
                }
                if let error=error {throw error}
                guard status != .error,buffer.frameLength>0 else {throw AudioError.invalid("选区重采样未完整输出，已取消拖出。")}
                let offset=result[0].count
                for c in 0..<2 {for i in 0..<Int(buffer.frameLength) {result[c].append(buffer.floatChannelData![c][i]*fade(at:start+offset+i,frames:count))}}
            }
            return result
        }
        return AudioDocument(rate:rate,channels:2,pieces:[Piece(asset:asset,offset:0,count:count)])
    }
    public static func write(_ audio:AudioDocument,range:Range<Int>,gain:SelectionGain?=nil,to destination:URL) throws {
        let cache=try AudioCache(),clip=try render(audio,range:range,gain:gain,cache:cache)
        try FileAudioWriter.write(clip,to:destination,encoding:.wav(rate:rate,channels:2,bits:24),exclusive:true)
    }
}
