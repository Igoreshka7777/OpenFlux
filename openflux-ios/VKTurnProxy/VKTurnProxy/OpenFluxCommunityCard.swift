import SwiftUI

/// The public community link is intentionally separate from VPN configuration.
struct OpenFluxCommunityCard: View {
    private let invite = URL(string: "https://vk.me/join/Q4Fgdl/Jvrd9w8i4C/_Actf/jM0U8/2Tc6E=")!

    var body: some View {
        Link(destination: invite) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    VKCommunityGlyph().fill(Color.white)
                        .frame(width: 58, height: 58)
                        .background(Color(red: 0, green: 0.47, blue: 1), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("НАША ГРУППА")
                            .font(.system(size: 10, weight: .medium)).tracking(1.6)
                            .foregroundColor(.white.opacity(0.75))
                        Text("ВКонтакте")
                            .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                        Text("Новости · Серверы · Поддержка")
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .medium)).foregroundColor(.white)
                }
                HStack {
                    Spacer(minLength: 0)
                    Text("ПЕРЕЙТИ В ГРУППУ").font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 18, weight: .medium))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [Color(red: 1, green: 0.43, blue: 0), OpenFluxStyle.orange], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 17))
            }
            .padding(17)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Color(red: 0.07, green: 0.055, blue: 0.05))
                    CommunityWave().stroke(OpenFluxStyle.orange.opacity(0.4), lineWidth: 2)
                        .blur(radius: 2)
                    CommunityWave().stroke(OpenFluxStyle.orange.opacity(0.14), lineWidth: 18)
                        .blur(radius: 12)
                }.clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(OpenFluxStyle.orange.opacity(0.75), lineWidth: 1))
            .shadow(color: OpenFluxStyle.orange.opacity(0.18), radius: 14, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ВКонтакте. Новости, серверы, поддержка. Перейти в группу")
    }
}

private struct CommunityWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -20, y: rect.height * 0.42))
        path.addCurve(to: CGPoint(x: rect.width + 20, y: rect.height * 0.45),
                      control1: CGPoint(x: rect.width * 0.3, y: rect.height * 1.18),
                      control2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.95))
        return path
    }
}

// VK mark from Simple Icons, CC0, on its original 24-point grid.
private struct VKCommunityGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 6.79000, y: 7.30000))
        path.addLine(to: CGPoint(x: 4.05000, y: 7.30000))
        path.addCurve(to: CGPoint(x: 12.77000, y: 17.29000), control1: CGPoint(x: 4.18000, y: 13.54000), control2: CGPoint(x: 7.30000, y: 17.29000))
        path.addLine(to: CGPoint(x: 13.08000, y: 17.29000))
        path.addLine(to: CGPoint(x: 13.08000, y: 13.72000))
        path.addCurve(to: CGPoint(x: 17.22000, y: 17.29000), control1: CGPoint(x: 15.09000, y: 13.92000), control2: CGPoint(x: 16.61000, y: 15.39000))
        path.addLine(to: CGPoint(x: 20.06000, y: 17.29000))
        path.addCurve(to: CGPoint(x: 15.95000, y: 12.28000), control1: CGPoint(x: 19.28000, y: 14.45000), control2: CGPoint(x: 17.23000, y: 12.88000))
        path.addCurve(to: CGPoint(x: 19.46000, y: 7.30000), control1: CGPoint(x: 17.23000, y: 11.54000), control2: CGPoint(x: 19.03000, y: 9.74000))
        path.addLine(to: CGPoint(x: 16.88000, y: 7.30000))
        path.addCurve(to: CGPoint(x: 13.08000, y: 11.25000), control1: CGPoint(x: 16.32000, y: 9.28000), control2: CGPoint(x: 14.66000, y: 11.08000))
        path.addLine(to: CGPoint(x: 13.08000, y: 7.30000))
        path.addLine(to: CGPoint(x: 10.50000, y: 7.30000))
        path.addLine(to: CGPoint(x: 10.50000, y: 14.22000))
        path.addCurve(to: CGPoint(x: 6.79000, y: 7.30000), control1: CGPoint(x: 8.90000, y: 13.82000), control2: CGPoint(x: 6.88000, y: 11.88000))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}
