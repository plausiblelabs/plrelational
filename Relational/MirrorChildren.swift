//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Mirror {
    var mirrorsIncludingSupertypes: [Mirror] {
        var result = [self]
        while let next = result.last?.superclassMirror {
            result.append(next)
        }
        return result
    }
    
    var childrenIncludingSupertypes: Children {
        let all = mirrorsIncludingSupertypes.flatMap({ $0.children })
        return AnyForwardCollection(all)
    }
}
