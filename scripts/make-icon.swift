import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
for size in [16,32,128,256,512] { for scale in [1,2] {
 let pixels=size*scale
 let image=NSImage(size:NSSize(width:pixels,height:pixels))
 image.lockFocus()
 let p=CGFloat(pixels),r=NSRect(x:p*0.05,y:p*0.05,width:p*0.9,height:p*0.9)
 NSColor(calibratedRed:0.08,green:0.14,blue:0.17,alpha:1).setFill();NSBezierPath(roundedRect:r,xRadius:p*0.21,yRadius:p*0.21).fill()
 let heights:[CGFloat]=[0.12,0.26,0.47,0.66,0.36,0.53,0.22]
 NSColor(calibratedRed:0.43,green:0.92,blue:0.76,alpha:1).setFill()
 for (i,h) in heights.enumerated() {
  let w=p*0.055,x=p*0.225+CGFloat(i)*p*0.083
  NSBezierPath(roundedRect:NSRect(x:x,y:(p-p*h)/2,width:w,height:p*h),xRadius:w/2,yRadius:w/2).fill()
 }
 image.unlockFocus()
 let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
 let filename="icon_\(size)x\(size)\(scale==2 ? "@2x" : "").png"
 try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(filename))
} }
