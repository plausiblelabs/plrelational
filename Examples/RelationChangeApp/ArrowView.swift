//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLBindableControls

private let maskH: CGFloat = 40

class ArrowView: NSView {

    private var bgLayer: CAShapeLayer!
    private var fgLayer: CAShapeLayer!
    private var maskLayer: CAGradientLayer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.wantsLayer = true
        
        let lw: CGFloat = 8
        
        func path() -> NSBezierPath {
            let b = self.bounds
            let p = NSBezierPath()
            let tip = CGPoint(x: b.midX, y: b.height - lw)
            let len: CGFloat = 24
            p.move(to: CGPoint(x: b.midX, y: lw))
            p.line(to: tip)
            p.move(to: CGPoint(x: lw, y: b.height - len))
            p.line(to: tip)
            p.move(to: CGPoint(x: b.width - lw, y: b.height - len))
            p.line(to: tip)
            return p
        }
        
        func addLayer(_ color: NSColor) -> CAShapeLayer {
            let l = CAShapeLayer()
            l.path = path().cgPath
            l.fillColor = NSColor.clear.cgColor
            l.strokeColor = color.cgColor
            l.lineWidth = lw
            l.lineCap = kCALineCapRound
            layer!.addSublayer(l)
            return l
        }
        
        bgLayer = addLayer(NSColor(white: 0.85, alpha: 1.0))
        fgLayer = addLayer(.green)
        
        let gradient = CAGradientLayer()
        gradient.anchorPoint = CGPoint(x: 0, y: 0)
        gradient.bounds = CGRect(x: 0, y: 0, width: frame.width, height: maskH)
        gradient.position = CGPoint(x: 0, y: -maskH)
        gradient.colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        fgLayer.mask = gradient
        maskLayer = gradient
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override var isFlipped: Bool {
        return true
    }

    func animate(delay: CFTimeInterval, duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: CGPoint(x: 0, y: -maskH))
        animation.toValue = NSValue(point: CGPoint(x: 0, y: self.bounds.height))
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.isRemovedOnCompletion = true
        maskLayer.add(animation, forKey: "position")
    }
}

extension NSBezierPath {
    
    public var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0 ..< self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            switch type {
            case .moveToBezierPathElement:
                path.move(to: points[0])
            case .lineToBezierPathElement:
                path.addLine(to: points[0])
            case .curveToBezierPathElement:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePathBezierPathElement:
                path.closeSubpath()
            }
        }
        
        return path
    }
}
