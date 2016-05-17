
import Foundation

extension Relation {
    public func fullDebugDump(showContents showContents: Bool = true) {
        fullDebugDump(showContents, 0)
    }
    
    func fullDebugDump(showContents: Bool, _ indent: Int) {
        let indentString = "".stringByPaddingToLength(indent * 4, withString: " ", startingAtIndex: 0)
        func print(str: String) {
            for line in str.componentsSeparatedByString("\n") {
                Swift.print("\(indentString)\(line)")
            }
        }
        
        print("\(self.dynamicType)")
        if showContents {
            print("\(self.description)")
        }
        
        let m = Mirror(reflecting: self)
        for (name, value) in m.children {
            if let name = name where !(value is Relation) && name != "changeObserverData" && name != "log" {
                print("\(name): \(value)")
            }
        }
        for (name, value) in m.children {
            if let name = name, let subrelation = value as? Relation {
                print("\(name):")
                subrelation.fullDebugDump(showContents, indent + 1)
            }
        }
    }
}
