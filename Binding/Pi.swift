//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

// Based on:
//   https://www.cs.cmu.edu/~wing/publications/Wing02a.pdf
//   https://github.com/alexj136/akka-pi/blob/master/src/main/scala/syntax.scala
//   https://github.com/typelift/Concurrent/blob/master/ConcurrentTests/PiCalculus.swift

typealias PiChannelName = String
typealias PiVariableName = String

indirect enum PiValue { case
    IntegerValue(Int),
    IncrInteger(PiVariableName),
    Channel(PiChannelName),
    Pair(PiValue, PiValue)
}

extension PiValue: CustomStringConvertible {
    var description: String {
        switch self {
        case let .IntegerValue(v):
            return "\(v)"
        case let .IncrInteger(name):
            return "\(name)+1"
        case let .Channel(name):
            return "\(name)"
        case let .Pair(l, r):
            return "\(l),\(r)"
        }
    }
}

indirect enum PiBinding { case
    Integer(PiVariableName),
    Channel(PiChannelName),
    Pair(PiBinding, PiBinding)
}

extension PiBinding: CustomStringConvertible {
    var description: String {
        switch self {
        case let .Integer(name):
            return "\(name)"
        case let .Channel(name):
            return "\(name)"
        case let .Pair(l, r):
            return "\(l),\(r)"
        }
    }
}

indirect enum Pi { case
    /// Run the two computations in parallel.
    Par(p: Pi, q: Pi),

    /// Create a new channel, then run the next computation.
    New(channel: PiChannelName, p: Pi),

    /// Send a value on the given channel, then run the next computation.
    Snd(channel: PiChannelName, value: PiValue, p: Pi),
    
    /// Receive a value on the given channel, then run the next computation.
    Rcv(channel: PiChannelName, binding: PiBinding, p: Pi),
    
    /// Terminate the process.
    End
}

extension Pi: CustomStringConvertible {
    var description: String {
        func dot(p: Pi) -> String {
            if case .End = p {
                return ""
            } else {
                return ".\(p)"
            }
        }
        
        switch self {
        case let Par(p, q):
            return "\(p) | \(q)"
        case let New(c, p):
            return "(nu \(c))(\(p))"
        case let Snd(c, m, p):
            return "\(c)<\(m)>\(dot(p))"
        case let Rcv(c, b, p):
            return "\(c)(\(b))\(dot(p))"
        case End:
            return ""
        }
    }
}

struct PiAgent {
}

typealias PiEnv = Dictionary<PiChannelName, PiAgent>

func runPi(pi: Pi, inout env: PiEnv) {
    // TODO
    print("PI: \(pi)")
}

func par(p: Pi, _ q: Pi) -> Pi {
    return .Par(p: p, q: q)
}

func newc(name: PiChannelName, then: Pi) -> Pi {
    return .New(channel: name, p: then)
}

func snd(on on: PiChannelName, value v: PiValueType, then: Pi = end) -> Pi {
    return .Snd(channel: on, value: v.value, p: then)
}

func rcv(on on: PiChannelName, bind b: PiBindingType, then: Pi = end) -> Pi {
    return .Rcv(channel: on, binding: b.binding, p: then)
}

func bpair(b0: PiChannelName, _ b1: PiVariableName) -> PiBinding {
    return .Pair(.Channel(b0), .Integer(b1))
}

func intb(name: PiVariableName) -> PiBinding {
    return .Integer(name)
}

func vpair(v0: PiChannelName, _ v1: Int) -> PiValue {
    return .Pair(.Channel(v0), .IntegerValue(v1))
}

func incr(b: PiVariableName) -> PiValue {
    return .IncrInteger(b)
}

let end: Pi = .End

infix operator *|* {
associativity left
}

func *|* (p: Pi, q: Pi) -> Pi {
    return par(p, q)
}

protocol PiValueType {
    var value: PiValue { get }
}

extension PiValue: PiValueType {
    var value: PiValue { return self }
}

extension String: PiValueType {
    var value: PiValue { return .Channel(self) }
}

protocol PiBindingType {
    var binding: PiBinding { get }
}

extension PiBinding: PiBindingType {
    var binding: PiBinding { return self }
}

extension String: PiBindingType {
    var binding: PiBinding { return .Channel(self) }
}
