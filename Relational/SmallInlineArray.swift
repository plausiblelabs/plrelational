//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

struct SmallInlineArray<T>: SequenceType {
    var localCount = 0
    
    var storage0: T?
    var storage1: T?
    var storage2: T?
    var storage3: T?
    var storage4: T?
    var storage5: T?
    var storage6: T?
    var storage7: T?
    var storage8: T?
    var storage9: T?
    
    var overflow: [T]?
    
    subscript(index: Int) -> T {
        get {
            switch index {
            case 0: return storage0!
            case 1: return storage1!
            case 2: return storage2!
            case 3: return storage3!
            case 4: return storage4!
            case 5: return storage5!
            case 6: return storage6!
            case 7: return storage7!
            case 8: return storage8!
            case 9: return storage9!
            default:
                return overflow![index - 10]
            }
        }
        set {
            switch index {
            case 0: storage0 = newValue
            case 1: storage1 = newValue
            case 2: storage2 = newValue
            case 3: storage3 = newValue
            case 4: storage4 = newValue
            case 5: storage5 = newValue
            case 6: storage6 = newValue
            case 7: storage7 = newValue
            case 8: storage8 = newValue
            case 9: storage9 = newValue
            default:
                overflow![index - 10] = newValue
            }
        }
    }
    
    var count: Int {
        return localCount + (overflow?.count ?? 0)
    }
    
    var isEmpty: Bool {
        return count == 0
    }
    
    var indices: Range<Int> {
        return 0..<count
    }
    
    mutating func append(value: T) {
        if localCount < 10 {
            self[localCount] = value
            localCount += 1
        } else {
            if overflow == nil {
                overflow = [value]
            } else {
                overflow!.append(value)
            }
        }
    }
    
    func generate() -> SmallInlineArrayGenerator<T> {
        return SmallInlineArrayGenerator(array: self)
    }
}

struct SmallInlineArrayGenerator<T>: GeneratorType {
    var array: SmallInlineArray<T>
    var cursor = 0
    
    init(array: SmallInlineArray<T>) {
        self.array = array
    }
    
    mutating func next() -> T? {
        if cursor < array.count {
            cursor += 1
            return array[cursor - 1]
        } else {
            return nil
        }
    }
}
