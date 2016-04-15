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
        let l = left.map({ $0.name }).joinWithSeparator(" ")
        let r = right.map({ $0.name }).joinWithSeparator(" ")
        return "\(l) -> \(r)"
    }
}

extension Relation {
    func satisfies(fd: FunctionalDependency) -> Bool {
        let leftValues = self.project(Scheme(attributes: fd.left))
        for row in leftValues.rows() {
            let rightRows = self.select(row).project(Scheme(attributes: fd.right))
            let gen = rightRows.rows()
            
            // See if there are two or more elements in rightRows
            gen.next()
            if gen.next() != nil {
                return false
            }
        }
        return false
    }
    
    func allSatisfiedFunctionalDependencies() -> [FunctionalDependency] {
        let allDependencies = self.scheme.attributes.powerSet.flatMap({ left in
            self.scheme.attributes.subtract(left).powerSet.map({ right in
                FunctionalDependency(left, determines: right)
            })
        })
        return allDependencies.filter({ self.satisfies($0) })
    }
}
