// Copyright (c) 2019 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import Foundation

/// Parses Swift Function times generated by `swiftc`
/// if you pass the flags `-Xfrontend -debug-time-function-bodies`
class SwiftCompilerFunctionTimeOptionParser: SwiftCompilerTimeOptionParser {

    private static let compilerFlag = "-debug-time-function-bodies"

    private static let invalidLoc = "<invalid loc>"

    private lazy var regexp: NSRegularExpression? = {
        let pattern = "[\\t*|\\r]([0-9]+\\.[0-9]+)ms\\t+(<invalid\\tloc>|[^\\t]+)\\t+(.+)\\r"
        return NSRegularExpression.fromPattern(pattern)
    }()

    func hasCompilerFlag(commandDesc: String) -> Bool {
        commandDesc.range(of: Self.compilerFlag) != nil
    }

    func parse(from commands: [String: Int]) -> [String: [SwiftFunctionTime]] {
        let functionsPerFile = commands.compactMap { parse(command: $0.key, occurrences: $0.value) }
            .joined().reduce([:]) { (functionsPerFile, functionTime)
        -> [String: [SwiftFunctionTime]] in
            var functionsPerFile = functionsPerFile
            if var functions = functionsPerFile[functionTime.file] {
                functions.append(functionTime)
                functionsPerFile[functionTime.file] = functions
            } else {
                functionsPerFile[functionTime.file] = [functionTime]
            }
            return functionsPerFile
        }
        return functionsPerFile
    }

    private func parse(command: String, occurrences: Int) -> [SwiftFunctionTime]? {
        guard let regexp = regexp else {
            return nil
        }
        let range = NSRange(location: 0, length: command.count)
        let matches = regexp.matches(in: command, options: .reportProgress, range: range)
        let functionTimes = matches.compactMap { result -> SwiftFunctionTime? in
            let durationString = command.substring(result.range(at: 1))
            let file = command.substring(result.range(at: 2))
            // some entries are invalid, we discard them
            if isInvalid(fileName: file) {
                return nil
            }

            let name = command.substring(result.range(at: 3))
            guard let (fileName, location) = parseFunctionLocation(file) else {
                return nil
            }
            let fileURL = prefixWithFileURL(fileName: fileName)
            guard let (line, column) = parseLocation(location) else {
                return nil
            }

            let duration = parseCompileDuration(durationString)
            return SwiftFunctionTime(file: fileURL,
                                durationMS: duration,
                                startingLine: line,
                                startingColumn: column,
                                signature: name,
                                occurrences: occurrences)
        }
        return functionTimes
    }

    private func parseFunctionLocation(_ function: String) -> (String, String)? {
        guard let colonIndex = function.firstIndex(of: ":") else {
            return nil
        }
        let functionName = function[..<colonIndex]
        let locationIndex = function.index(after: colonIndex)
        let location = function[locationIndex...]

        return (String(functionName), String(location))
    }

    private func parseLocation(_ location: String) -> (Int, Int)? {
        guard let colonIndex = location.firstIndex(of: ":") else {
            return nil
        }
        let line = location[..<colonIndex]
        let columnIndex = location.index(after: colonIndex)
        let column = location[columnIndex...]
        guard let lineNumber = Int(String(line)),
            let columnNumber = Int(String(column)) else {
                return nil
        }
        return (lineNumber, columnNumber)
    }

}
