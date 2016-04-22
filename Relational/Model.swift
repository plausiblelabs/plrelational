
protocol Model: class {
    static var name: String { get }
    static var attributes: [Attribute] { get }
    
    func toRow() -> Row
    static func fromRow(owningDatabase: ModelDatabase, _ row: Row) -> Self
    
    var objectID: Int64? { get set }
}
