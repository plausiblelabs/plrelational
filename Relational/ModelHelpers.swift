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


func ConvertToInt64(value: Value) -> Int64 {
    return Int64(value)!
}

func ConvertFromInt64(int64: Int64) -> Value {
    return String(int64)
}
