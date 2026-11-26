import Foundation

public enum TimeUnit: String, CaseIterable, Codable {
    case clock = "时间", samples = "样本"
    public func format(_ frames: Int, rate: Double) -> String {
        if self == .samples { return String(frames) }
        let seconds=Double(frames)/rate
        let whole=Int(seconds), fraction=seconds-Double(whole)
        // Six decimals preserve sample identity at supported sample rates when round-tripping.
        return String(format:"%02d:%02d:%09.6f",whole/3600,(whole/60)%60,Double(whole%60)+fraction)
    }
    public func parse(_ text: String, rate: Double) throws -> Int {
        let input=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if self == .samples {
            guard let frame=Int(input),frame>=0 else {throw AudioError.invalid("样本位置必须是非负整数。")};return frame
        }
        let fields=input.split(separator:":",omittingEmptySubsequences:false)
        guard (1...3).contains(fields.count) else {throw AudioError.invalid("时间格式为 时:分:秒，也可直接输入秒数。")}
        var seconds=0.0
        for (i,field) in fields.enumerated() {
            guard let n=Double(field),n.isFinite,n>=0,(i==0 || n<60), (i==fields.count-1 || n.rounded()==n) else {throw AudioError.invalid("时间格式无效，请使用 时:分:秒 或十进制秒。")}
            seconds=seconds*60+n
        }
        let frames=seconds*rate
        guard frames.isFinite,frames<Double(Int.max),rate.isFinite,rate>0 else {throw AudioError.invalid("时间超出可用范围。")}
        return Int(frames.rounded())
    }
}

public struct SelectionGesture {
    public var anchor: Int
    public var head: Int
    public init(anchor:Int,head:Int) {self.anchor=anchor;self.head=head}
    public var range:Range<Int> { min(anchor,head)..<max(anchor,head) }
    public mutating func move(by delta:Int,limit:Int) {head=max(0,min(limit,head+delta))}
}
public struct Viewport {
    public var start:Double
    public var length:Double
    public init(start:Double,length:Double) {self.start=start;self.length=length}
    public func zoomed(factor:Double,anchor:Double,total:Double) -> Viewport {
        guard factor.isFinite,factor>0 else{return self}
        let fraction=max(0,min(1,(anchor-start)/max(1,length)))
        let newLength=max(1,min(max(1,total),length/factor))
        return Viewport(start:max(0,min(max(0,total-newLength),anchor-fraction*newLength)),length:newLength)
    }
}
public struct SourceMeter {
    public var values:[Float] = [0,0]
    public var holds:[Float] = [0,0]
    public var clipped:[Bool] = [false,false]
    public init() {}
    public mutating func ingest(_ peaks:[Float]) {
        for c in 0..<2 {
            let p=c<peaks.count && peaks[c].isFinite ? max(0,peaks[c]) : 0
            values[c]=max(p,values[c]*0.72);holds[c]=max(holds[c],p);clipped[c]=clipped[c] || p>=1
        }
    }
    public mutating func stop() {values=[0,0]}
    public mutating func reset() {values=[0,0];holds=[0,0];clipped=[false,false]}
}

// A click may contain fractional-point pointer jitter. Only a deliberate horizontal
// drag starts a new selection; resizing an existing edge stays sample precise.
public struct SelectionDrag {
    public let startX:Double
    public private(set) var isSelecting:Bool
    public init(startX:Double,precise:Bool=false) {self.startX=startX;self.isSelecting=precise}
    public mutating func update(x:Double) -> Bool {
        if abs(x-startX)>=3 {isSelecting=true}
        return isSelecting
    }
}
