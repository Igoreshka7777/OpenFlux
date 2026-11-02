import SwiftUI

struct SubscriptionGlowControl: View {
    var level:Double
    let status:String
    let days:String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var displayLevel:Double=0
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:reduceMotion || scenePhase != .active || displayLevel<=0)) { timeline in
            let phase=timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:5.5)/5.5 * .pi*2
            let pulse=reduceMotion ? 0.75 : 0.775-0.225*cos(phase)
            ZStack {
                GlowCanvas(level:displayLevel,pulse:pulse)
                VStack(spacing:8) {
                    Image(systemName:"power").font(.system(size:40,weight:.light)).foregroundColor(Color(red:1,green:0.79,blue:0.54))
                        .padding(.bottom,4)
                    Text(status).font(.system(size:17,weight:.medium))
                    Text(days).font(.system(size:14)).foregroundColor(Color(red:0.91,green:0.8,blue:0.71))
                }.foregroundColor(Color(red:1,green:0.93,blue:0.85))
            }
        }.frame(maxWidth:340).aspectRatio(1,contentMode:.fit).contentShape(Circle())
        .onAppear {displayLevel=min(1,max(0,level))}
        .onChange(of:level) {v in withAnimation(reduceMotion ? nil : .easeInOut(duration:0.9)){displayLevel=min(1,max(0,v))}}
    }
}
private struct GlowCanvas:View,Animatable {
    var level:Double
    var pulse:Double
    var animatableData:Double {get{level} set{level=newValue}}
    var body:some View {
        Canvas {context,size in
            let r=min(size.width,size.height)*0.325
            let center=CGPoint(x:size.width/2,y:size.height/2)
            if level>0 {
                let outer=r+min(size.width,size.height)*(0.025+0.14*level)
                let halo=Path(ellipseIn:CGRect(x:center.x-outer,y:center.y-outer,width:outer*2,height:outer*2))
                context.fill(halo,with:.radialGradient(Gradient(stops:[.init(color:.clear,location:0),.init(color:.clear,location:0.62),.init(color:Color(red:1,green:0.54,blue:0.21).opacity(0.45*level*pulse),location:0.72),.init(color:Color(red:1,green:0.40,blue:0.10).opacity(0.23*level*pulse),location:0.83),.init(color:.clear,location:1)]),center:center,startRadius:0,endRadius:outer))
            }
            let circle=Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2))
            context.fill(circle,with:.radialGradient(Gradient(colors:[Color(red:0.114,green:0.051,blue:0.031),Color(red:0.043,green:0.035,blue:0.031)]),center:center,startRadius:0,endRadius:r))
            context.stroke(circle,with:.linearGradient(Gradient(colors:[Color(red:1,green:0.82,blue:0.52),Color(red:1,green:0.46,blue:0.15)]),startPoint:.zero,endPoint:CGPoint(x:size.width,y:size.height)),lineWidth:1.7)
        }
    }
}
