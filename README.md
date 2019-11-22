# PLRelational

PLRelational is a data storage, processing, and presentation framework based on relational algebra. It is written in Swift and is available for macOS and iOS.

## License

PLRelational is released under an MIT license. See the LICENSE file for the full license.

## Quick Start

The repository contains `PLRelational.xcodeproj` which will build out of the box. You can manually build the frameworks and add them to your project, or you can add the PLRelational project as a dependency.

## Frameworks

The PLRelational project provides two primary frameworks:

* **PLRelational** provides all of the core data storage and processing facilities. It includes relations backed by plists, SQLite, or stored in memory, operators on those relations, full text search facilities, asynchronous data updates and retrieval, and more.
* **PLRelationalCombine** builds on the PLRelational and Combine frameworks with publishers that present relations as a stream of values and/or changes. It also includes array-optimized publishers, support for bidirectional bindings via the `@TwoWay` property wrapper, and more.

_Note that this repository contains sources for two other legacy frameworks, PLRelationalBinding and PLBindableControls.  These were originally developed (back in 2015-16) as experimental reactive/binding layers that provide the reactive glue to connect PLRelational with AppKit/UIKit.  With the advent of the Combine and SwiftUI frameworks in 2019, those legacy frameworks are no longer worth maintaining and will be retired in the near future._

## Playground

The `PLRelationalExamples.xcodeproj` under the `Examples` directory contains a Swift playground that serves as a thorough introduction to PLRelational.  

Here are a few samples taken from that playground to get you started:

### Building a model with relations

The first step in building an application with PLRelational is to
define its model, which entails describing each Relation and
populating them with some initial data.

```swift
import PLRelational

// Describe the relations
let employees = MakeRelation(["emp_id", "first_name", "last_name", "dept_id"])
let departments = MakeRelation(["dept_id", "title"])

// Add some departments
func addDepartment(_ id: Int64, _ title: String) {
    departments.add([
        "dept_id": id,
        "title": title
    ])
}
addDepartment(1, "Executive")
addDepartment(2, "Safety")

// Print the content of the `departments` relation
print(departments)

// Add some employees
func addEmployee(_ id: Int64, _ first: String, _ last: String, _ deptID: Int64) {
    employees.add([
        "emp_id": id,
        "first_name": first,
        "last_name": last,
        "dept_id": deptID
    ])
}
addEmployee(1, "Montgomery", "Burns", 1)
addEmployee(2, "Waylon", "Smithers", 1)
addEmployee(3, "Homer", "Simpson", 2)
addEmployee(4, "Lenny", "Leonard", 2)
addEmployee(5, "Carl", "Carlson", 2)

// Print the content of the `employees` relation
print(employees)
```

### Playing with relations

Now that we've defined some relations, we can have fun
with relational algebra.  Use `join` to combine relations,
`select` to narrow the focus on a subset of rows, and
`project` to focus on a subset of attributes ("columns").

These are just a few of the relational algebra operators
that are provided with PLRelational.

```swift
// Select an employee by `id` and project just his first name
let homer = employees
    .select(Attribute("emp_id") *== 3)
    .project("first_name")
print(homer)

// Simulate a master/detail application by marking Homer
// as "selected"
let selectedEmployeeID = MakeRelation(["emp_id"])
selectedEmployeeID.add(["emp_id": 3])

// Create a complex relation by joining the three source
// relations; this will contain the selected person's name and
// department info
let selectedEmployee = selectedEmployeeID
    .join(employees)
    .join(departments)
print(selectedEmployee)
```

### Observing relation changes using Combine

The real power of PLRelational is in being able to make changes
to your relations, and then observing and reacting to those changes.

PLRelational includes Combine extensions (i.e., custom publishers)
that make it possible to subscribe to the contents of a Relation
and transform those contents in various ways.

```swift
import PLRelationalCombine

// In the following chain, `oneString` will create a `Publisher`
// that emits the current selected employee's first name, along
// with any changes that are made to that value over time
var cancellable = selectedEmployee
    .project("first_name")
    .oneString()
    .logError()
    .sink {
	// Print the latest value to the console
        Swift.print($0)
    }

// The current value ("Montgomery") should have been delivered to
// our `sink` (after the initial asynchronous query has finished)
Async.awaitAsyncCompletion()
// (sink will print "Montgomery")

// Make Lenny the selected employee, and see that the publisher
// emits the new "first name" value.  Note that we're using the
// `asyncUpdateInteger` convenience, which is a useful shorthand
// for updating a single-attribute relation.
selectedEmployeeID.asyncUpdateInteger(4)
Async.awaitAsyncCompletion()
// (sink will print "Lenny")

// One way to change his first name would be to modify the
// original (source) relation
employees.asyncUpdate(Attribute("emp_id") *== 4, newValues: ["first_name": "Len"])
Async.awaitAsyncCompletion()
// (sink will print "Len")

// However, it's also possible to modify the source relation
// by applying an update to a higher-level (view) relation.
// In this scenario, we've created a relation that
// focuses in on the selected employee's first name,
// and then apply the update directly to that relation.
// Note that the change is applied to the underlying
// source relation, but our publisher also sees the
// new value.
let selectedEmployeeFirstName = selectedEmployee.project("first_name")
selectedEmployeeFirstName.asyncUpdateString("Lenford")
Async.awaitAsyncCompletion()
// (sink will print "Lenford")

// We can confirm that the underlying source relation was updated
print(employees)

// Cancel the subscription when we're finished
cancellable.cancel()
```

### Using PLRelational[Combine] + SwiftUI to build a UI

Here is an example of using SwiftUI to build a small form,
with editable text fields for the person's first and last
name, and a label that displays the employee's department.

Note the use of PLRelational's `@TwoWay` property wrapper.  This is
similar to Combine's `@Published`, except that it allows for
plugging in different behaviors when the value is set via the property's
setter.

The `bind` function works in conjunction with `@TwoWay` and lets
you specify a "strategy" that takes care of reading values from the
underlying relation, and writing values back to that relation.  It also
handles the special logic that prevents feedback loops that might
otherwise occur when the underlying relation is updated.

```swift
import SwiftUI

class DetailViewModel: ObservableObject {
    @TwoWay var firstName: String = ""
    @TwoWay var lastName: String = ""
    @Published var department: String = ""
    
    private var cancellableBag = CancellableBag()
    
    init(model: Model) {
        // The selected employee's first name (read/write)
        model.selectedEmployee
            .project("first_name")
            .bind(to: \._firstName, on: self, strategy: oneString)
            .store(in: &cancellableBag)

        // The selected employee's last name (read/write)
        model.selectedEmployee
            .project("last_name")
            .bind(to: \._lastName, on: self, strategy: oneString)
            .store(in: &cancellableBag)

        // The selected employee's department title (read-only)
        model.selectedEmployee
            .join(model.departments)
            .project("title")
            .oneString()
            .logError()
            .bind(to: \.department, on: self)
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.cancel()
    }
    
    func commitFirstName() {
        _firstName.commit()
    }
    
    func commitLastName() {
        _lastName.commit()
    }
}

struct DetailView: View {
    @ObservedObject var model: DetailViewModel

    var body: some View {
        VStack(alignment: .leading) {
            TextField("First name", text: $model.firstName, onCommit: model.commitFirstName)
            TextField("Last name", text: $model.lastName, onCommit: model.commitLastName)
            Divider()
            Text("Department: \(model.department)")
            Spacer()
        }
        .padding()
    }
}
```

## Examples

The `PLRelationalExamples` Xcode project includes a number of example apps:

* **TodoApp-SwiftUI** is a realistic to-do app built with PLRelational[Combine] and SwiftUI, that runs on both macOS and iOS.

Additionally, there are some AppKit-based apps for macOS that were developed using the legacy PLRelationalBinding framework.  These will be migrated to use PLRelationalCombine + SwiftUI in due time:

* **HelloWorldApp** is the best place to start; a minimal example that demonstrates relations, binding, undo/redo, etc.
* **TodoApp** is a good example of using PLRelational to build a real-world, working to-do app.
* **SearchApp** demonstrates the use of `RelationTextIndex` for full text search.
* **BindableControlsApp** is primarily a UI testing target for all the AppKit controls in PLBindableControls.
* **Visualizer** contains the beginnings of a visual tool (very much a work in progress) for creating and debugging relations.

## Acknowledgements

The PLRelational collection of frameworks draws inspiration from and stands on the shoulders of many other works, chief among them the earliest relational research from E.F. Codd, et al, [Out of the Tar Pit](https://github.com/papers-we-love/papers-we-love/blob/master/design/out-of-the-tar-pit.pdf) by Ben Moseley and Peter Marks, [Push-Pull Functional Reactive Programming](http://conal.net/papers/push-pull-frp) by Conal Elliott, and the many incarnations of Rx such as [ReactiveSwift](https://github.com/ReactiveCocoa/ReactiveSwift).  Thanks also to [Landon Fuller](https://twitter.com/landonfuller) for his continued advice and for planting the seeds that resulted in the earliest prototypes.

## Further Reading

For more depth on these frameworks, check out the following blog posts:
* [Reactive Relational Programming with PLRelational](https://plausible.coop/blog/2017/08/10/reactive-relational-programming-with-plrelational)
* [An Introduction to Relational Algebra Using PLRelational](https://plausible.coop/blog/2017/08/24/intro-to-relational-algebra-using-plrelational)
* [PLRelational: Observing Change](https://plausible.coop/blog/2017/08/29/plrelational-observing-change)
* [PLRelational: Storage Formats](https://plausible.coop/blog/2017/09/07/plrelational-storage-formats)
* [Let's Build with PLRelational, Part 1](https://plausible.coop/blog/2017/09/18/build-with-plrelational-part-1)
* [Let's Build with PLRelational, Part 2](https://plausible.coop/blog/2017/09/28/build-with-plrelational-part-2)
* [PLRelational: Query Optimization and Execution](https://plausible.coop/blog/2017/10/03/plrelational-query-optimization)

Generated documentation is also [available online](https://plausiblelabs.github.io/plrelational/docs/current) for the PLRelational and PLRelationalBinding frameworks.

Enjoy!
