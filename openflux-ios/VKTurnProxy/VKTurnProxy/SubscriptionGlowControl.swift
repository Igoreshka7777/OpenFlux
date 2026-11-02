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
            render(context:&context,size:size)
        }
    }
    private func circle(_ center:CGPoint,_ radius:Double)->Path {
        Path(ellipseIn:CGRect(x:Double(center.x)-radius,y:Double(center.y)-radius,width:radius*2,height:radius*2))
    }
    private func render(context:inout GraphicsContext,size:CGSize) {
        let dimension=Double(min(size.width,size.height))
        let r=dimension*0.29
        let center=CGPoint(x:size.width/2,y:size.height/2)
        if level>0 && connectionGlow>0 {drawHalo(context:&context,center:center,r:r,dimension:dimension)}
        if collecting && !reduceMotion {drawRays(context:&context,center:center,r:r,dimension:dimension)}
        if wave<1 && !reduceMotion {drawWaves(context:&context,center:center,r:r,dimension:dimension)}
        let core=circle(center,r)
        context.fill(core,with:.color(.black))
        let orange=Color(red:1.0,green:100.0/255.0,blue:18.0/255.0)
        context.stroke(core,with:.color(orange),lineWidth:1.6)
    }
    private func drawHalo(context:inout GraphicsContext,center:CGPoint,r:Double,dimension:Double) {
        let outer=r+dimension*(0.025+0.42*level)
        let edge=r/outer
        var stops=[Gradient.Stop]()
        let orange=Color(red:1.0,green:100.0/255.0,blue:18.0/255.0)
        for i in 0...129 {
            let t:Double=i==0 ? 0.0 : Double(i-1)/128.0
            let pattern:Double=reduceMotion ? 1.0 : 0.65+0.35*cos(t*12.0-phase*2.0)
            let tail:Double=1.0-t*t
            let falloff:Double=exp(-2.8*t*t)*tail*tail
            let strength:Double=level*pulse*connectionGlow
            let alpha:Double=i==129 ? 0.0 : strength*pattern*falloff
            let location:Double=i==0 ? 0.0 : edge+(1.0-edge)*t
            stops.append(Gradient.Stop(color:orange.opacity(alpha),location:CGFloat(location)))
        }
        let shading=GraphicsContext.Shading.radialGradient(Gradient(stops:stops),center:center,startRadius:0,endRadius:CGFloat(outer))
        context.fill(circle(center,outer),with:shading)
    }
    private func drawRays(context:inout GraphicsContext,center:CGPoint,r:Double,dimension:Double) {
        for i in 0..<18 {
            let t=(collectionPhase+Double(i)/18.0).truncatingRemainder(dividingBy:1.0)
            let a=Double(i)*2.0*Double.pi/18.0
            let distance=r+dimension*0.22*(1.0-t)
            let sx=Double(center.x)+cos(a)*distance
            let sy=Double(center.y)+sin(a)*distance
            let length=14.0*(1.0-t)
            var ray=Path();ray.move(to:CGPoint(x:sx,y:sy))
            ray.addLine(to:CGPoint(x:sx+cos(a)*length,y:sy+sin(a)*length))
            let color=Color(red:1.0,green:170.0/255.0,blue:102.0/255.0).opacity(sin(t*Double.pi)*0.8)
            context.stroke(ray,with:.color(color),lineWidth:1.5)
        }
    }
    private func drawWaves(context:inout GraphicsContext,center:CGPoint,r:Double,dimension:Double) {
        for i in 0...1 {
            let t=min(1.0,max(0.0,(wave-Double(i)*0.1)/0.9))
            let radius=r+dimension*0.6*t
            let alpha=(1.0-t)*(1.0-t)*0.7
            let color=Color(red:1.0,green:152.0/255.0,blue:76.0/255.0).opacity(alpha)
            context.stroke(circle(center,radius),with:.color(color),lineWidth:CGFloat(2.0+4.0*t))
        }
    }
}
