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
    
    init(frame: CGRect, dual: Bool) {
        super.init(frame: frame)
        
        self.wantsLayer = true
        
        let lw: CGFloat = 8
        
        func straightPath() -> NSBezierPath {
            let b = self.bounds
            let p = NSBezierPath()
            let tip = CGPoint(x: b.midX, y: b.height - lw)
            let tipH: CGFloat = 20
            p.move(to: CGPoint(x: b.midX, y: lw))
            p.line(to: tip)
            p.move(to: CGPoint(x: lw, y: b.height - tipH))
            p.line(to: tip)
            p.move(to: CGPoint(x: b.width - lw, y: b.height - tipH))
            p.line(to: tip)
            return p
        }
        
        func curvyPath() -> NSBezierPath {
            // TODO: Make straightPath use the same width always
            let tipW: CGFloat = 40
            let halfTipW: CGFloat = tipW * 0.5
            let tipH: CGFloat = 20
            let b = self.bounds
            let p = NSBezierPath()
            let tipTop = CGPoint(x: b.midX, y: b.height - tipH)
            let tipBot = CGPoint(x: b.midX, y: b.height - lw)
            let leftCtrl1 = CGPoint(x: halfTipW, y: b.height - lw)
            let leftCtrl2 = CGPoint(x: tipBot.x, y: lw)
            let rightCtrl1 = CGPoint(x: b.width - halfTipW, y: b.height - lw)
            let rightCtrl2 = CGPoint(x: tipBot.x, y: lw)
            p.move(to: CGPoint(x: halfTipW, y: lw))
            p.curve(to: tipTop, controlPoint1: leftCtrl1, controlPoint2: leftCtrl2)
            p.move(to: CGPoint(x: b.width - halfTipW, y: lw))
            p.curve(to: tipTop, controlPoint1: rightCtrl1, controlPoint2: rightCtrl2)
            p.line(to: tipBot)
            p.move(to: CGPoint(x: tipTop.x - halfTipW + lw, y: b.height - tipH))
            p.line(to: tipBot)
            p.move(to: CGPoint(x: tipTop.x + halfTipW - lw, y: b.height - tipH))
            p.line(to: tipBot)
            return p
        }
        
        func addLayer(_ path: NSBezierPath, _ color: NSColor) -> CAShapeLayer {
            let l = CAShapeLayer()
            l.path = path.cgPath
            l.fillColor = NSColor.clear.cgColor
            l.strokeColor = color.cgColor
            l.lineWidth = lw
            l.lineCap = kCALineCapRound
            layer!.addSublayer(l)
            return l
        }
        
        let path = dual ? curvyPath() : straightPath()
        bgLayer = addLayer(path, NSColor(white: 0.85, alpha: 1.0))
        fgLayer = addLayer(path, .green)
        
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
    
    func animate(color: NSColor, delay: CFTimeInterval, duration: CFTimeInterval) {
        fgLayer.strokeColor = color.cgColor
        
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: CGPoint(x: 0, y: -maskH))
        animation.toValue = NSValue(point: CGPoint(x: 0, y: self.bounds.height))
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.isRemovedOnCompletion = true
        maskLayer.add(animation, forKey: "position")
    }
}
