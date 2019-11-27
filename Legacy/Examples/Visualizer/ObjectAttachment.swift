//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

private var associatedObjectKey = UnsafeMutablePointer<Int8>.allocate(capacity: 1)

/// Attach an object to another object. This can be used for turning weak/unowned
/// properties into de-facto strong properties by attaching the target of the
/// property to the object that contains the property. Good for standalone delegates
/// and action targets.
///
/// - parameter object: The target object whose lifetime will be extended.
/// - parameter to: The source object to attach to.
/// - returns: `object`, for easier chaining of calls.
func attach<T: AnyObject>(_ object: T, to: AnyObject) -> T{
    objc_sync_enter(to)
    
    let array = objc_getAssociatedObject(to, associatedObjectKey) as? NSArray ?? []
    let newArray = array.adding(object)
    objc_setAssociatedObject(to, associatedObjectKey, newArray, .OBJC_ASSOCIATION_RETAIN)
    
    objc_sync_exit(to)
    
    return object
}
