func ConvertToString(value: Value) -> String {
    return value
}

func ConvertFromString(string: String) -> Value {
    return string
}


func ConvertToInt(value: Value) -> Int {
    return Int(value)!
}

func ConvertFromInt(int: Int) -> Value {
    return String(int)
}


func ConvertToUInt64(value: Value) -> UInt64 {
    return UInt64(value)!
}

func ConvertFromUInt64(uint64: UInt64) -> Value {
    return String(uint64)
}
