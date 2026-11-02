import SwiftUI

struct SubscriptionGlowControl: View {
    var level:Double
    let status:String
    let days:String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var displayLevel:Double=0
    @State private var connectionGlow:Double=0
    @State private var waveStart:Date?=nil
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/60,paused:reduceMotion || scenePhase != .active || (connectionGlow<=0 && !status.hasPrefix("Подключение")))) { timeline in
            let phase=timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:4.2)/4.2 * .pi*2
            let pulse=reduceMotion ? 0.9 : 0.88
            ZStack {
                GlowCanvas(level:displayLevel,pulse:pulse,connectionGlow:connectionGlow,phase:phase,reduceMotion:reduceMotion,
                    collecting:status.hasPrefix("Подключение"),
                    collectionPhase:timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:1.1)/1.1,
                    wave:waveStart.map{min(1,max(0,timeline.date.timeIntervalSince($0)/1.5))} ?? 1)
                VStack(spacing:8) {
                    Image(systemName:"power").font(.system(size:40,weight:.light)).foregroundColor(Color(red:1,green:0.72,blue:0.40))
                        .padding(.bottom,4)
                    Text(status).font(.system(size:17,weight:.medium))
                }.foregroundColor(Color(red:1,green:0.93,blue:0.85))
            }
        }.frame(maxWidth:380).aspectRatio(1,contentMode:.fit).contentShape(Circle())
        .onAppear {displayLevel=min(1,max(0,level));connectionGlow=status=="Подключено" ? 1 : 0}
        .onChange(of:status) {v in
            waveStart=v=="Подключено" && !reduceMotion ? Date() : nil
            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.65)){connectionGlow=v=="Подключено" ? 1 : 0}
        }
        .onChange(of:level) {v in withAnimation(reduceMotion ? nil : .easeInOut(duration:0.9)){displayLevel=min(1,max(0,v))}}
    }
}
private struct GlowCanvas:View,Animatable {
    var level:Double
    var pulse:Double
    var connectionGlow:Double
    var phase:Double
    var reduceMotion:Bool
    var collecting:Bool
    var collectionPhase:Double
    var wave:Double
    var animatableData:AnimatablePair<Double,Double> {get{AnimatablePair(level,connectionGlow)} set{level=newValue.first;connectionGlow=newValue.second}}
    var body:some View {
        Canvas {context,size in
            let r=min(size.width,size.height)*0.29
            let center=CGPoint(x:size.width/2,y:size.height/2)
            if level>0 && connectionGlow>0 {
                let outer=r+min(size.width,size.height)*(0.025+0.42*level)
                let edge=r/outer
                let stops:[Gradient.Stop]=(0...129).map {i in
                    let t=i==0 ? 0 : Double(i-1)/128
                    let pattern=reduceMotion ? 1.0 : 0.65+0.35*cos(t*12-phase*2)
                    let alpha=i==129 ? 0 : level*pulse*connectionGlow*pattern*exp(-2.8*t*t)*(1-t*t)*(1-t*t)
                    return .init(color:Color(red:1,green:100/255,blue:18/255).opacity(alpha),location:i==0 ? 0 : edge+(1-edge)*t)
                }
                let halo=Path(ellipseIn:CGRect(x:center.x-outer,y:center.y-outer,width:outer*2,height:outer*2))
                context.fill(halo,with:.radialGradient(Gradient(stops:stops),center:center,startRadius:0,endRadius:outer))
            }
            if collecting && !reduceMotion {
                for i in 0..<18 {
                    let t=(collectionPhase+Double(i)/18).truncatingRemainder(dividingBy:1)
                    let a=Double(i)*2*Double.pi/18
                    let distance=r+min(size.width,size.height)*0.22*(1-t)
                    let start=CGPoint(x:center.x+cos(a)*distance,y:center.y+sin(a)*distance)
                    var ray=Path();ray.move(to:start)
                    ray.addLine(to:CGPoint(x:start.x+cos(a)*14*(1-t),y:start.y+sin(a)*14*(1-t)))
                    context.stroke(ray,with:.color(Color(red:1,green:170/255,blue:102/255).opacity(sin(t * .pi)*0.8)),lineWidth:1.5)
                }
            }
            if wave<1 && !reduceMotion {
                for i in 0...1 {
                    let t=min(1,max(0,(wave-Double(i)*0.1)/0.9))
                    let radius=r+min(size.width,size.height)*0.6*t
                    let ring=Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2))
                    context.stroke(ring,with:.color(Color(red:1,green:152/255,blue:76/255).opacity((1-t)*(1-t)*0.7)),lineWidth:2+4*t)
                }
            }
            let circle=Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2))
            context.fill(circle,with:.color(.black))
            context.stroke(circle,with:.color(Color(red:1,green:100/255,blue:18/255)),lineWidth:1.6)
        }
    }
}
