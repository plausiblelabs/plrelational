//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

enum AsyncState<T> {
    case idle(T)
    case loading
}
