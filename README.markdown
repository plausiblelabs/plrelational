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

## Further Reading

For more information about PLRelational, see our series of blog posts located here: https://example.com/REPLACEME

Documentation generated from documentation comments is available online here: https://example.com/REPLACEME

Enjoy!
