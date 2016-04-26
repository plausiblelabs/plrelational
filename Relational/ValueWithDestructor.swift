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
