func ConvertToString(value: Value) -> String {
    return value
}

func ConvertToInt(value: Value) -> Int {
    return Int(value)!
}

func ConvertFromString(string: String) -> Value {
    return string
}

func ConvertFromInt(int: Int) -> Value {
    return String(int)
}
