# PLRelational

PLRelational is a data storage, processing, and presentation framework based on relational algebra. It is written in Swift and is available for macOS and iOS.

## License

PLRelational is released under an MIT license. See the LICENSE file for the full license.

## Quick Start

The repository contains `PLRelational.xcodeproj` which will build out of the box. You can manually build the frameworks and add them to your project, or you can add the PLRelational project as a dependency.

Here is some quick code to exercise it:

    import PLRelational
    import PLRelationalBinding
    import PLBindableControls
    
    // Set up relations
    let people = MemoryTableRelation(scheme: ["id", "name", "age"])
    let selectedPersonID = MemoryTableRelation(scheme: ["id"])
    let selectedPerson = people.join(selectedPersonID)
    let selectedName = selectedPerson.project("name")
    
    // Add initial data
    people.asyncAdd(["id": 1, "name": "John Doe", "age": 42])
    people.asyncAdd(["id": 2, "name": "Superman", "age": 35])
    people.asyncAdd(["id": 3, "name": "Hugh Mann", "age": 78])
    selectedPersonID.asyncAdd(["id": 2])
    
    // Query the selected name
    selectedName.asyncAllRows({ print($0) })
    // Prints "Ok(Set([[name: Superman]]))" when the data comes back

    // Create a property that presents the selected name relation as a single String
    let selectedNameString = selectedName.oneString().property()
    
    // Observe changes to the selected name
    let removal = selectedNameString.signal.observeValueChanging{ value, metadata in
        print("Selected name is now \(value)")
    }
    
    // Remove the observer when done
    removal()
    
    // Create a label and bind it to the selected name
    let label = Label()
    label.string <~ selectedNameString

## Frameworks

The PLRelational project provides three frameworks:

* **PLRelational** provides all of the core data storage and processing facilities. It includes relations backed by plists, SQLite, or stored in memory, operators on those relations, full text search facilities, asynchronous data updates and retrieval, and more.
* **PLRelationalBinding** provides the reactive glue to connect PLRelational's relations to other entities. At its base it provides `Signal` and `Property` types which are abstract data providers, as well as extensions that allow a relation to be expressed in terms of them.
* **PLBindableControls** extends standard AppKit and UIKit controls to expose `Property` objects from PLRelationalBinding. This allows those controls to be linked to relations from PLRelational, which causes them to automatically reflect the current value of a relation, or update that value based on user interaction.

Typically you will use all three together, but PLRelational can be used standalone, and PLRelationalBinding can be used without PLBindableControls.

## Examples

The Xcode project includes a number of example apps for macOS:

* **HelloWorldApp** is the best place to start; a minimal example that demonstrates relations, binding, undo/redo, etc.
* **SearchApp** demonstrates the use of `RelationTextIndex` for full text search.
* **BindableControlsApp** is primarily a UI testing target for all the AppKit controls in PLBindableControls.
* **Visualizer** contains the beginnings of a visual tool (very much a work in progress) for creating and debugging relations.

## Acknowledgements

The PLRelational collection of frameworks draws inspiration from and stands on the shoulders of many other works, chief among them the earliest relational research from E.F. Codd, et al, [Out of the Tar Pit](https://github.com/papers-we-love/papers-we-love/blob/master/design/out-of-the-tar-pit.pdf) by Ben Moseley and Peter Marks, [Push-Pull Functional Reactive Programming](http://conal.net/papers/push-pull-frp) by Conal Elliott, and the many incarnations of Rx such as [ReactiveSwift](https://github.com/ReactiveCocoa/ReactiveSwift).  Thanks also to [Landon Fuller](https://twitter.com/landonfuller) for his continued advice and for planting the seeds that resulted in the earliest prototypes.

## Further Reading

For a more in-depth introduction to these frameworks, check out [Reactive Relational Programming with PLRelational](https://plausible.coop/blog/2017/08/10/reactive-relational-programming-with-plrelational).

Generated documentation is also [available online](https://opensource.plausible.coop/plrelational/docs/current) for the PLRelational and PLRelationalBinding frameworks.

Enjoy!
