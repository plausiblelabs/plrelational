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

enum TemplateLineComponent {
    case Text(String)
    case ModelName
    case FieldName
    case FieldType
}

struct TemplateLine {
    var components: [TemplateLineComponent]
    
    var containsFieldComponent: Bool {
        return components.contains({
            switch $0 {
            case .FieldName, .FieldType: return true
            default: return false
            }
        })
    }
    
    func render(modelName modelName: String, fieldName: String? = nil, fieldType: String? = nil) -> String {
        let textComponents = components.map({ component -> String in
            switch component {
            case .Text(let text):
                return text
            case .ModelName:
                return modelName
            case .FieldName:
                return fieldName!
            case .FieldType:
                return fieldType!
            }
        })
        
        return textComponents.joinWithSeparator("")
    }
}

func trim(string: String) -> String {
    return string.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
}

class ValueWithDestructor<T> {
    var value: T
    let destructor: T -> Void
    
    init(value: T, destructor: T -> Void) {
        self.value = value
        self.destructor = destructor
    }
    
    deinit {
        destructor(value)
    }
}

func ReadFileByLine(path: String) -> AnyGenerator<String> {
    let file = ValueWithDestructor(value: fopen(path, "r"), destructor: { fclose($0) })
    precondition(file.value != nil, "Failed to open file at \(path)")
    
    let lineBuffer = ValueWithDestructor<UnsafeMutablePointer<Int8>>(value: nil, destructor: { free($0) })
    var capacity = 0
    
    return AnyGenerator(body: {
        let chars = getline(&lineBuffer.value, &capacity, file.value)
        if chars == -1 { return nil }
        
        return String(format: "%.*s", chars, lineBuffer.value)
    })
}

func ReadModels(path: String) -> [Model] {
    var results: [Model] = []
    
    for (index, line) in ReadFileByLine(path).enumerate() {
        func error(message: String) {
            let lineNumber = index + 1
            fputs("\(path):\(lineNumber): error: \(message)", stderr)
            exit(1)
        }
        
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

func ReadTemplate(path: String) -> [TemplateLine] {
    let specialTokens = [
        "MODELNAME": TemplateLineComponent.ModelName,
        "FIELDNAME": TemplateLineComponent.FieldName,
        "FIELDTYPE": TemplateLineComponent.FieldType,
    ]
    
    let specialTokensRegex = specialTokens.keys.map(NSRegularExpression.escapedPatternForString).joinWithSeparator("|")
    let regex = try! NSRegularExpression(pattern: specialTokensRegex, options: [])
    
    var result: [TemplateLine] = []
    
    for line in ReadFileByLine(path) {
        let nsline = line as NSString
        let matches = regex.matchesInString(line, options: [], range: NSRange(location: 0, length: nsline.length))
        let ranges = matches.map({ $0.range })
        
        let rangesWithDummyBeginning = [NSRange(location: 0, length: 0)] + ranges
        let rangesWithDummyEnd = ranges + [NSRange(location: nsline.length, length: 0)]
        
        var line: [TemplateLineComponent] = []
        
        for (first, second) in zip(rangesWithDummyBeginning, rangesWithDummyEnd) {
            if first.length != 0 {
                let specialToken = nsline.substringWithRange(first)
                line.append(specialTokens[specialToken]!)
            }
            
            let between = NSRange(location: NSMaxRange(first), length: second.location - NSMaxRange(first))
            if between.length != 0 {
                let text = nsline.substringWithRange(between)
                line.append(.Text(text))
            }
        }
        
        result.append(TemplateLine(components: line))
    }
    
    return result
}

func WriteModels(models: [Model], _ template: [TemplateLine], _ path: String) {
    let file = fopen(path, "w")
    defer { fclose(file) }
    
    for model in models {
        for line in template {
            if line.containsFieldComponent {
                for field in model.fields {
                    let output = line.render(modelName: model.name, fieldName: field.name, fieldType: field.type)
                    fputs(output, file)
                }
            } else {
                let output = line.render(modelName: model.name)
                fputs(output, file)
            }
        }
    }
}

func Parse(model inpath: String, template: String, out outpath: String) {
    let models = ReadModels(inpath)
    let template = ReadTemplate(template)
    WriteModels(models, template, outpath)
}

func main() {
    let args = Process.arguments
    
    if args.count != 3 {
        fputs("usage: \(args[0]) <input> <output>", stderr)
    }
    
    let templatePath = ((args[0] as NSString).stringByDeletingLastPathComponent as NSString).stringByAppendingPathComponent("genmodel.template")
    
    Parse(model: args[1], template: templatePath, out: args[2])
}

main()
