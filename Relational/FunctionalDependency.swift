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
        var result = true
        leftValues.forEach({ row, stop in
            let rightRows = self.select(row).project(Scheme(attributes: fd.right))
            var count = 0
            rightRows.forEach({ row, stop in
                count += 1
                if count > 1 {
                    result = false
                    stop()
                }
            })
            if result == false {
                stop()
            }
        })
        return result
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
