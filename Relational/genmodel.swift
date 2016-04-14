#!/usr/bin/env xcrun swift

import Foundation

struct Model {
    struct Field {
        var name: String
        var type: String
    }
    
    var name: String
    var fields: [Field]
}

func trim(string: String) -> String {
    return string.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
}

func ReadModels(path: String) -> [Model] {
    let file = fopen(path, "r")
    defer { fclose(file) }
    
    var results: [Model] = []
    
    var buffer: UnsafeMutablePointer<Int8> = nil
    var capacity = 0
    var lineNumber = 0
    while true {
        func error(message: String) {
            fputs("\(path):\(lineNumber): error: \(message)", stderr)
            exit(1)
        }
        
        lineNumber += 1
        let chars = getline(&buffer, &capacity, file)
        if chars == -1 { break }
        
        let line = String(format: "%.*s", chars, buffer)
        let trimmedLine = trim(line)
        guard !trimmedLine.isEmpty else { continue }
        
        if isspace(Int32(line.utf8.first!)) == 0 {
            if trimmedLine.characters.last != ":" {
                error("Model name '\(trimmedLine)' must end with a colon")
            }
            
            let name = String(trimmedLine.characters.dropLast())
            results.append(Model(name: name, fields: []))
        } else {
            if results.isEmpty {
                error("Field declaration must appear after a model declaration")
            }
            
            let components = trimmedLine.componentsSeparatedByString(":")
            if components.count < 2 {
                error("Field declaration must contain a colon")
            } else if components.count > 2 {
                error("Field declaration must contain only one colon")
            }
            
            let name = trim(components[0])
            let type = trim(components[1])
            if name.isEmpty {
                error("Field name must not be empty")
            }
            if type.isEmpty {
                error("Field type must not be empty")
            }
            
            results[results.count - 1].fields.append(Model.Field(name: name, type: type))
        }
    }
    
    return results
}

func WriteModels(models: [Model], _ path: String) {
    let file = fopen(path, "w")
    defer { fclose(file) }
    
    func putline(line: String) {
        fputs(line, file)
        fputs("\n", file)
    }
    for model in models {
        putline("struct \(model.name) {")
        for field in model.fields {
            putline("    var \(field.name): \(field.type)")
        }
        putline("    static func fromRow(row: Row) -> \(model.name) {")
        putline("        return \(model.name)(")
        for (index, field) in model.fields.enumerate() {
            let comma = index < model.fields.count - 1 ? "," : ""
            putline("            \(field.name): ConvertTo\(field.type)(row[\"\(field.name)\"])\(comma)")
        }
        putline("        )")
        putline("    }")
        putline("")
        putline("    func toRow() -> Row {")
        putline("        return Row(values: [")
        for field in model.fields {
            putline("            \"\(field.name)\": ConvertFrom\(field.type)(\(field.name)),")
        }
        putline("        ])")
        putline("    }")
        putline("}")
        putline("")
    }
}

func Parse(inpath: String, _ outpath: String) {
    let models = ReadModels(inpath)
    WriteModels(models, outpath)
}

let args = Process.arguments

if args.count != 3 {
    fputs("usage: \(args[0]) <input> <output>", stderr)
}

Parse(args[1], args[2])
