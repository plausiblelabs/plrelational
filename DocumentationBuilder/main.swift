//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// Usage:
///    DocumentationBuilder [--directory <target-directory>] [--output <output-directory>] [TargetName ...]

import Foundation


let sourcekitten = "sourcekitten"
let jazzy = "jazzy"


func defaultWorkingDirectory(_ file: String = #file) -> String {
    return ((file as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
}

func fail(_ string: String) -> Never {
    fputs("error: \(string)\n", stderr)
    exit(1)
}

func shellProcess(_ args: [String]) -> Process {
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-l", "-c", "env \"$@\"", "-c"] + args
    return process
}

func has(command: String) -> Bool {
    let process = shellProcess(["which", command])
    process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
    process.launch()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

func run(stdin: Data? = nil, _ args: [String]) -> Data {
    fputs(args.joined(separator: " ") + "\n", stderr)
    
    let process = shellProcess(args)
    
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    
    process.launch()
    
    let stdinFile = stdinPipe.fileHandleForWriting
    if let stdin = stdin {
        DispatchQueue.global().async(execute: {
            stdinFile.write(stdin)
            stdinFile.closeFile()
        })
    } else {
        stdinFile.closeFile()
    }
    
    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        fail("execution failed with exit code \(process.terminationStatus)")
    }
    return data
}

func parseArguments() -> (directory: String, outputDirectory: String, targets: [(module: String, target: String)]) {
    var directory = defaultWorkingDirectory()
    var outputDirectory = (directory as NSString).appendingPathComponent("docs")
    var targets: [(module: String, target: String)] = []
    
    var iterator = CommandLine.arguments.makeIterator()
    
    // Skip the process name
    _ = iterator.next()
    
    while let arg = iterator.next() {
        switch arg {
        case "--directory":
            guard let arg2 = iterator.next() else {
                fail("missing argument for --directory flag")
            }
            directory = arg2
        case "--output":
            guard let arg2 = iterator.next() else {
                fail("missing argument for --output flag")
            }
            outputDirectory = arg2
        default:
            let module = arg.components(separatedBy: "-")[0]
            targets.append((module: module, target: arg))
        }
    }
    
    return (directory, outputDirectory, targets)
}

let hasSK = has(command: sourcekitten)
let hasJazzy = has(command: jazzy)
guard hasSK && hasJazzy else {
    let processName = CommandLine.arguments.first ?? "<unknown>"
    fputs("error: \(processName): missing dependencies\n", stderr)
    if !hasSK {
        fputs("    Requires sourcekitten command. https://github.com/jpsim/SourceKitten - sudo port install sourcekitten\n", stderr)
    }
    if !hasJazzy {
        fputs("    Requirez jazzy command. https://github.com/realm/jazzy - sudo gem install jazzy\n", stderr)
    }
    exit(1)
}

let args = parseArguments()
FileManager.default.changeCurrentDirectoryPath(args.directory)

var JSONs: [Any] = []
for (module, target) in args.targets {
    do {
        let output = run(["sourcekitten", "doc", "--module-name", module, "--", "-target", target])
        let json = try JSONSerialization.jsonObject(with: output, options: [])
        guard let jsonArray = json as? [Any] else {
            fail("JSON produced non-array top level object of type \(type(of: json))")
        }
        JSONs.append(contentsOf: jsonArray)
    } catch {
        fail("JSON deserialization failed: \(error)")
    }
}

do {
    let combinedJSON = try JSONSerialization.data(withJSONObject: JSONs, options: [])
    _ = run(stdin: combinedJSON, ["jazzy", "--output", args.outputDirectory, "--clean", "--sourcekitten-sourcefile", "/dev/stdin"])
} catch {
    fail("JSON serialization failed: \(error)")
}
