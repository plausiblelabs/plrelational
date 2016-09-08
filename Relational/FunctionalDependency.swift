//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

struct FunctionalDependency {
    var left: Set<Attribute>
    var right: Set<Attribute>
    
    init(_ left: Set<Attribute>, determines right: Set<Attribute>) {
        self.left = left
        self.right = right
    }
}

extension FunctionalDependency: CustomStringConvertible {
    var description: String {
        let l = left.map({ $0.name }).joined(separator: " ")
        let r = right.map({ $0.name }).joined(separator: " ")
        return "\(l) -> \(r)"
    }
}

extension Relation {
    func satisfies(_ fd: FunctionalDependency) -> Result<Bool, RelationError> {
        let leftValues = self.project(Scheme(attributes: fd.left))
        for row in leftValues.rows() {
            switch row {
            case .Ok(let row):
                let rightRows = self.select(row).project(Scheme(attributes: fd.right))
                let gen = rightRows.rows()
                
                // See if there are two or more elements in rightRows
                gen.next()
                if gen.next() != nil {
                    return .Ok(false)
                }
            case .Err(let error):
                return .Err(error)
            }
        }
        return .Ok(true)
    }
    
    func allSatisfiedFunctionalDependencies() -> Result<[FunctionalDependency], RelationError> {
        let allDependencies = self.scheme.attributes.powerSet.flatMap({ left in
            self.scheme.attributes.subtracting(left).powerSet.map({ right in
                FunctionalDependency(left, determines: right)
            })
        })
        
        var result: [FunctionalDependency] = []
        for dependency in allDependencies {
            switch self.satisfies(dependency) {
            case .Ok(true):
                result.append(dependency)
            case .Err(let e):
                return .Err(e)
            default:
                break
            }
        }
        return .Ok(result)
    }
}
