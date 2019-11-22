// Copyright (c) 2019 Plausible Labs Cooperative, Inc.

//#-hidden-code
import PlaygroundSupport
PlaygroundPage.current.needsIndefiniteExecution = true
//#-end-hidden-code

/*:
 ## Building a model with relations
 
 The first step in building an application with _PLRelational_ is to\
 define its model, which entails describing each `Relation` and\
 populating them with some initial data.
 
 For this example, we'll define one relation that contains employee\
 data for Springfield Nuclear Power Plant, and another to hold some\
 department names.
*/

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
departments

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
employees



/*:
 ## Playing with relations
 
 Now that we've defined some relations, we can have fun\
 with relational algebra.  Use `join` to combine relations,\
 `select` to narrow the focus on a subset of rows, and\
 `project` to focus on a subset of attributes ("columns").
 
 These are just a few of the relational algebra operators\
 that are provided with _PLRelational_.
*/

// Select an employee by `id` and project just his first name
let homer = employees
    .select(Attribute("emp_id") *== 3)
    .project("first_name")
homer

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
selectedEmployee

// Pretend we're creating a "badge view" for the selected
// employee that contains just the first name and department
let selectedEmployeeBadge = selectedEmployee
    .projectRenamed(["first_name": "first", "title": "dept_title"])
selectedEmployeeBadge

// Now change the "selected" employee in the source relation
// and see that our derived "badge" relation reflects the
// updated values
selectedEmployeeID.update(true, newValues: ["emp_id": 1])
selectedEmployeeBadge



/*:
 ## Observing relation changes using _Combine_
 
 The real power of _PLRelational_ is in being able to make changes\
 to your relations, and then observing and reacting to those changes.
 
 There are some low-level observer protocols that allow you to\
 observe both fine-grained and coalesced changes to a `Relation`,\
 but it's often easier to think in terms of a reactive "stream"\
 like what the _Combine_ framework offers.

 _PLRelational_ includes _Combine_ extensions (i.e., custom publishers)\
 that make it possible to subscribe to the contents of a `Relation`\
 and transform those contents in various ways.
*/

import PLRelationalCombine

// In the following chain, `oneString` will create a `Publisher`
// that emits the current selected employee's first name, along
// with any changes that are made to that value over time
var latestFirstName = "none"
var cancellable = selectedEmployee
    .project("first_name")
    .oneString()
    .logError()
    .sink {
        // Save the latest value to a variable
        latestFirstName = $0
    }

// (This is just a way to wait for PLRelational's async
// operations to complete synchronously; not typically
// used in real applications)
Async.awaitAsyncCompletion()

// The current value ("Montgomery") should have been delivered to
// our `sink` (after the initial asynchronous query has finished)
latestFirstName

// Make Lenny the selected employee, and see that the publisher
// emits the new "first name" value.  Note that we're using the
// `asyncUpdateInteger` convenience, which is a useful shorthand
// for updating a single-attribute relation.
selectedEmployeeID.asyncUpdateInteger(4)
Async.awaitAsyncCompletion()
latestFirstName

// One way to change his first name would be to modify the
// original (source) relation
employees.asyncUpdate(Attribute("emp_id") *== 4, newValues: ["first_name": "Len"])
Async.awaitAsyncCompletion()
latestFirstName

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
latestFirstName

// We can confirm that the underlying source relation was updated
employees

// Cancel the subscription when we're finished
cancellable.cancel()



/*:
 ## Mapping a relation to an array of structs
 
 As we've seen above, _PLRelational_ makes it easy to focus on a single value\
 within a relation, but sometimes (like when displaying a `List` view)\
 it's useful to convert a relation's raw rows to Swift structs.
 
 _PLRelational_ offers a couple different ways of mapping the contents of\
 a relation to an array.  The easiest way is to use the `mapSorted` function,\
 as demonstrated below.
*/

struct Employee: Identifiable {
    let id: Int64
    let firstName: String
    let lastName: String
    
    init(_ row: Row) {
        self.id = row["emp_id"].get()!
        self.firstName = row["first_name"].get()!
        self.lastName = row["last_name"].get()!
    }
}

// Create a new relation that represents the "selected" department,
// and mark the "Executive" department as selected
let selectedDepartmentID = MakeRelation(["dept_id"], [1])

// Create a new `Publisher` that maps the employee rows for
// the selected department to an array of `Employee` instances,
// sorted by last name
var latestEmployees: [Employee] = []
cancellable = selectedDepartmentID
    .join(employees)
    .map(Employee.init, sortedBy: { $0.lastName < $1.lastName })
    .logError()
    .sink {
        // Save the latest array to a variable
        latestEmployees = $0
    }

// The current set of executives (Burns and Smithers) should have
// been delivered to our `sink` (after the initial asynchronous
// query has finished)
Async.awaitAsyncCompletion()
latestEmployees

// Now suppose we give Lenny a promotion; after we update his
// department ID, we should see him appear in the set of executives
employees.asyncUpdate(Attribute("emp_id") *== 4, newValues: ["dept_id": 1])
Async.awaitAsyncCompletion()
latestEmployees

// Cancel the subscription when we're finished
cancellable.cancel()



/*:
 ## Building an app with _SwiftUI_ and _PLRelational_
 
 We can use an MVVM ("Model + View + View Model") approach to building\
 a user interface on top of the relations we defined earlier.
*/
/*:
 ### 1. Define the Model
 
 First, we'll wrap the relations we created earlier in a Model struct\
 that's easier to pass around
*/
struct Model {
    let employees: MutableRelation
    let departments: MutableRelation
    let selectedEmployeeID: MutableRelation
    let selectedEmployee: Relation
}
let model = Model(
    employees: employees,
    departments: departments,
    selectedEmployeeID: selectedEmployeeID,
    selectedEmployee: selectedEmployee
)

/*:
 ### 2. Define the "master" View and View Model
 
 This is basically a thin wrapper around a _SwiftUI_ `List` view that is bound\
 to our `employees` relation.
 
 When the list selection changes, we update the underlying\
 `selectedEmployeeID`  relation.  The detail view will then update\
 itself automatically to reflect the selected employee.
*/
import SwiftUI

class MasterViewModel: ObservableObject {
    @Published var employees: [Employee] = []
    var selectedEmployeeId: Int64? {
        didSet {
            // Update the underlying relation when the list selection changes
            self.model.selectedEmployeeID
                .asyncReplaceInteger(selectedEmployeeId)
        }
    }
    
    private let model: Model
    private var cancellableBag = CancellableBag()
    
    init(model: Model) {
        self.model = model
        
        // Map the `employees` relation to an array of `Employee` instances
        model.employees
            .map(Employee.init, sortedBy: { $0.lastName < $1.lastName })
            .logError()
            .bind(to: \.employees, on: self)
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.cancel()
    }
}

struct MasterView: View {
    @ObservedObject var model: MasterViewModel

    var body: some View {
        List(selection: $model.selectedEmployeeId) {
            ForEach(model.employees) { emp in
                Text("\(emp.lastName), \(emp.firstName)")
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    .animation(nil)
            }
        }
        .animation(.default)
    }
}

let masterViewModel = MasterViewModel(model: model)
Async.awaitAsyncCompletion()
let masterPreview = MasterView(model: masterViewModel)
    .frame(width: 200, height: 160)
masterPreview

/*:
 ### 3. Define the "detail" View and View Model
 
 This is a small form, with editable text fields for the person's first and last\
 name, and a label that displays the employee's department.
 
 Note the use of _PLRelational's_ `@TwoWay` property wrapper.  This is\
 similar to _Combine's_ `@Published`, except that it allows for\
 plugging in different behaviors when the value is set via the property's\
 setter.
 
 The `bind` function works in conjunction with `@TwoWay` and lets\
 you specify a "strategy" that takes care of reading values from the\
 underlying relation, and writing values back to that relation.  It also\
 handles the special logic that prevents feedback loops that might\
 otherwise occur when the underlying relation is updated.
*/
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

let detailViewModel = DetailViewModel(model: model)
Async.awaitAsyncCompletion()
let detailPreview = DetailView(model: detailViewModel)
    .frame(width: 200, height: 200)
detailPreview

/*:
 ### 4. Tie it all together
 
 Create a split view, with the list view on the left and the detail\
 view on the right.
*/

struct ContentViewModel {
    let masterViewModel: MasterViewModel
    let detailViewModel: DetailViewModel
}

struct ContentView: View {
    var model: ContentViewModel

    var body: some View {
        HStack(spacing: 0) {
            MasterView(model: model.masterViewModel)
                .frame(minWidth: 160)
            DetailView(model: model.detailViewModel)
                .frame(minWidth: 180)
        }
        .padding()
    }
}

let contentViewModel = ContentViewModel(
    masterViewModel: masterViewModel,
    detailViewModel: detailViewModel
)
let contentView = ContentView(model: contentViewModel)
    .frame(width: 340, height: 180)
contentView

// TODO: Unfortunately, SwiftUI's List view doesn't
// seem to update its selection highlighting when
// the underlying property changes programatically,
// so the cell won't be highlighted after the following
contentViewModel.masterViewModel.selectedEmployeeId = 3
Async.awaitAsyncCompletion()
contentView

/*:
 ### 5. Play with the live view
 
 Load the UI we just built into the playground's "live view",\
 then select different employees in the list view and watch\
 the detail view update in response.
*/

// Run to here to see this UI in the live view
let liveContentView = ContentView(model: contentViewModel)
    .frame(width: 340, height: 220)
PlaygroundPage.current.setLiveView(liveContentView)

// You can also type in the text fields to change
// the selected employee's name, and see that the
// list view updates automatically when you hit
// enter or change focus to a different field.
// Uncomment and run the following to see a
// simulation of that kind of edit.
//DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//    detailViewModel.lastName = "Appleby"
//    detailViewModel.commitLastName()
//}
