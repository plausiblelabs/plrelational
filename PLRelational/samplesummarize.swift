#!/usr/bin/swift

import Foundation

class ValueWithDestructor<T> {
    var value: T
    let destructor: T -> Void
    
    init(value: T, destructor: T -> Void) {
        self.value = value
        self.destructor = destructor
    }
    
    deinit {
        destructor(value)
    }
}

func ReadFileByLine(path: String) -> AnyGenerator<String> {
    let file = ValueWithDestructor(value: fopen(path, "r"), destructor: { fclose($0) })
    precondition(file.value != nil, "Failed to open file at \(path)")
    
    let lineBuffer = ValueWithDestructor<UnsafeMutablePointer<Int8>>(value: nil, destructor: { free($0) })
    var capacity = 0
    
    return AnyGenerator(body: {
        let chars = getline(&lineBuffer.value, &capacity, file.value)
        if chars == -1 { return nil }
        
        return String(format: "%.*s", chars, lineBuffer.value)
    })
}

func Parse(path: String) {
    let numbers = NSCharacterSet(charactersInString: "0123456789")
    
    var counts: [String: Int] = [:]
    for line in ReadFileByLine(path).lazy.filter({ $0.hasPrefix("    +") }) {
        let countRange = line.rangeOfCharacterFromSet(numbers)!
        let lineWithoutIndentation = line.substringFromIndex(countRange.startIndex)
        
        let endRange = lineWithoutIndentation.rangeOfString("  (")!
        let lineWithoutTrailer = lineWithoutIndentation.substringToIndex(endRange.startIndex)
        
        let countEndRange = lineWithoutTrailer.rangeOfString(" ")!
        let countString = lineWithoutTrailer.substringToIndex(countEndRange.startIndex)
        let symbolString = lineWithoutTrailer.substringFromIndex(countEndRange.endIndex)
        
        let count = Int(countString)!
        
        counts[symbolString] = count + (counts[symbolString] ?? 0)
    }
    let sorted = counts.sort({ $0.1 < $1.1 })
    for (name, count) in sorted {
        print("\(count): \(name)")
    }
}

func main() {
    let args = Process.arguments
    
    if args.count != 2 {
        fputs("usage: \(args[0]) <samplefile>\n", stderr)
        exit(1)
    }
    
    Parse(args[1])
}

main()
