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
    integerValue(Int),
    incrInteger(PiVariableName),
    channel(PiChannelName),
    pair(PiValue, PiValue)
}

extension PiValue: CustomStringConvertible {
    var description: String {
        switch self {
        case let .integerValue(v):
            return "\(v)"
        case let .incrInteger(name):
            return "\(name)+1"
        case let .channel(name):
            return "\(name)"
        case let .pair(l, r):
            return "\(l),\(r)"
        }
    }
}

indirect enum PiBinding { case
    integer(PiVariableName),
    channel(PiChannelName),
    pair(PiBinding, PiBinding)
}

extension PiBinding: CustomStringConvertible {
    var description: String {
        switch self {
        case let .integer(name):
            return "\(name)"
        case let .channel(name):
            return "\(name)"
        case let .pair(l, r):
            return "\(l),\(r)"
        }
    }
}

indirect enum Pi { case
    /// Run the two computations in parallel.
    par(p: Pi, q: Pi),

    /// Create a new channel, then run the next computation.
    new(channel: PiChannelName, p: Pi),

    /// Send a value on the given channel, then run the next computation.
    snd(channel: PiChannelName, value: PiValue, p: Pi),
    
    /// Receive a value on the given channel, then run the next computation.
    rcv(channel: PiChannelName, binding: PiBinding, p: Pi),
    
    /// Terminate the process.
    end
}

extension Pi: CustomStringConvertible {
    var description: String {
        func dot(_ p: Pi) -> String {
            if case .end = p {
                return ""
            } else {
                return ".\(p)"
            }
        }
        
        switch self {
        case let .par(p, q):
            return "\(p) | \(q)"
        case let .new(c, p):
            return "(nu \(c))(\(p))"
        case let .snd(c, m, p):
            return "\(c)<\(m)>\(dot(p))"
        case let .rcv(c, b, p):
            return "\(c)(\(b))\(dot(p))"
        case .end:
            return ""
        }
    }
}

struct PiAgent {
}

typealias PiEnv = Dictionary<PiChannelName, PiAgent>

func runPi(_ pi: Pi, env: inout PiEnv) {
    // TODO
    print("PI: \(pi)")
}

func par(_ p: Pi, _ q: Pi) -> Pi {
    return .par(p: p, q: q)
}

func newc(_ name: PiChannelName, then: Pi) -> Pi {
    return .new(channel: name, p: then)
}

func snd(on: PiChannelName, value v: PiValueType, then: Pi = end) -> Pi {
    return .snd(channel: on, value: v.value, p: then)
}

func rcv(on: PiChannelName, bind b: PiBindingType, then: Pi = end) -> Pi {
    return .rcv(channel: on, binding: b.binding, p: then)
}

func bpair(_ b0: PiChannelName, _ b1: PiVariableName) -> PiBinding {
    return .pair(.channel(b0), .integer(b1))
}

func intb(_ name: PiVariableName) -> PiBinding {
    return .integer(name)
}

func vpair(_ v0: PiChannelName, _ v1: Int) -> PiValue {
    return .pair(.channel(v0), .integerValue(v1))
}

func incr(_ b: PiVariableName) -> PiValue {
    return .incrInteger(b)
}

let end: Pi = .end

precedencegroup PiPrecedence {
    associativity: left
}

infix operator *|* : PiPrecedence

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
    var value: PiValue { return .channel(self) }
}

protocol PiBindingType {
    var binding: PiBinding { get }
}

extension PiBinding: PiBindingType {
    var binding: PiBinding { return self }
}

extension String: PiBindingType {
    var binding: PiBinding { return .channel(self) }
}
