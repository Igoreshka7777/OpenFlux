import SwiftUI

struct SubscriptionGlowControl: View {
    var level:Double
    let status:String
    let days:String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var displayLevel:Double=0
    @State private var rim:Double=0
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/60,paused:reduceMotion || scenePhase != .active || displayLevel<=0)) { timeline in
            let phase=timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:5.5)/5.5 * .pi*2
            let pulse=reduceMotion ? 0.9 : 0.89-0.11*cos(phase)
            ZStack {
                GlowCanvas(level:displayLevel,pulse:pulse,rim:rim)
                VStack(spacing:8) {
                    Image(systemName:"power").font(.system(size:40,weight:.light)).foregroundColor(Color(red:1,green:0.72,blue:0.40))
                        .padding(.bottom,4)
                    Text(status).font(.system(size:17,weight:.medium))
                    Text(days).font(.system(size:14)).foregroundColor(Color(red:0.91,green:0.8,blue:0.71))
                }.foregroundColor(Color(red:1,green:0.93,blue:0.85))
            }
        }.frame(maxWidth:340).aspectRatio(1,contentMode:.fit).contentShape(Circle())
        .onAppear {displayLevel=min(1,max(0,level));rim=status=="Подключено" ? 1 : 0}
        .onChange(of:status) {v in withAnimation(reduceMotion ? nil : .easeInOut(duration:0.65)){rim=v=="Подключено" ? 1 : 0}}
        .onChange(of:level) {v in withAnimation(reduceMotion ? nil : .easeInOut(duration:0.9)){displayLevel=min(1,max(0,v))}}
    }
}
private struct GlowCanvas:View,Animatable {
    var level:Double
    var pulse:Double
    var rim:Double
    var animatableData:Double {get{level} set{level=newValue}}
    var body:some View {
        Canvas {context,size in
            let r=min(size.width,size.height)*0.325
            let center=CGPoint(x:size.width/2,y:size.height/2)
            if level>0 {
                let outer=r+min(size.width,size.height)*(0.025+0.145*level)
                let edge=r/outer
                let stops:[Gradient.Stop]=(0...33).map {i in
                    let t=i==0 ? 0 : Double(i-1)/32
                    let alpha=i==33 ? 0 : 0.824*level*pulse*exp(-5*t*t)
                    return .init(color:Color(red:1,green:100/255,blue:18/255).opacity(alpha),location:i==0 ? 0 : edge+(1-edge)*t)
                }
                let halo=Path(ellipseIn:CGRect(x:center.x-outer,y:center.y-outer,width:outer*2,height:outer*2))
                context.fill(halo,with:.radialGradient(Gradient(stops:stops),center:center,startRadius:0,endRadius:outer))
            }
            let circle=Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2))
            context.fill(circle,with:.linearGradient(Gradient(colors:[Color(red:37/255,green:13/255,blue:4/255),Color(red:13/255,green:8/255,blue:5/255)]),startPoint:.zero,endPoint:CGPoint(x:0,y:size.height)))
            context.stroke(circle,with:.linearGradient(Gradient(colors:[Color(red:1,green:178/255,blue:77/255).opacity(rim),Color(red:1,green:121/255,blue:22/255).opacity(rim)]),startPoint:.zero,endPoint:CGPoint(x:size.width,y:size.height)),lineWidth:1.6)
        }
    }
}
