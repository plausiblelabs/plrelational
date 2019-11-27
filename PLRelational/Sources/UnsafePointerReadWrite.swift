//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


import Darwin

extension UnsafeRawPointer {
    func unalignedLoad<T: ExpressibleByIntegerLiteral>(fromByteOffset: Int) -> T {
        var output: T = 0
        memcpy(&output, self + fromByteOffset, MemoryLayout<T>.size)
        return output
    }
}

extension UnsafePointer {
    func unalignedLoad<T: ExpressibleByIntegerLiteral>(fromByteOffset: Int) -> T {
        return UnsafeRawPointer(self).unalignedLoad(fromByteOffset: fromByteOffset)
    }
}
