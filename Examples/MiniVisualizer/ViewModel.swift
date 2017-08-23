//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding
import PLBindableControls

enum Fruit {
    static let id = Attribute("id")
    static let name = Attribute("name")
    static let quantity = Attribute("quantity")
}

class ViewModel {
    
    private let db: TransactionalDatabase
    private let fruits: TransactionalRelation
    
    private var observerRemovals: [ObserverRemoval] = []
    
    init() {
        // Prepare the stored relations
        let memoryDB = MemoryTableDatabase()
        let db = TransactionalDatabase(memoryDB)
        func createRelation(_ name: String, _ scheme: Scheme) -> TransactionalRelation {
            _ = memoryDB.createRelation(name, scheme: scheme)
            return db[name]
        }
        
        fruits = createRelation(
            "fruit",
            [Fruit.id, Fruit.name, Fruit.quantity])
        
        self.db = db
        
        fruits.asyncAdd([Fruit.id: 1, Fruit.name: "Apple", Fruit.quantity: 5])
        fruits.asyncAdd([Fruit.id: 2, Fruit.name: "Banana", Fruit.quantity: 7])
        fruits.asyncAdd([Fruit.id: 3, Fruit.name: "Cherry", Fruit.quantity: 42])
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
    
    lazy var fruitsProperty: ArrayProperty<RowArrayElement> = {
        return self.fruits.arrayProperty(idAttr: Fruit.id, orderAttr: Fruit.id)
    }()
}
