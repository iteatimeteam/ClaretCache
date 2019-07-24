#!/usr/bin/env xcrun --sdk macosx swift

import Foundation

func run(targetPath: String) {
    let relativePath = CommandLine.arguments[0] as NSString
    let configFilePath = relativePath.deletingLastPathComponent + "/.swiftlint.yml"
    let configFileUrl = URL(fileURLWithPath: configFilePath)
    let configPath = configFileUrl.path
    let launchPath = relativePath.deletingLastPathComponent.components(separatedBy: "/..").first! + "/../Pods/SwiftLint/swiftlint"

    let process = Process()
    process.launchPath = launchPath
    process.arguments = ["lint", "--config", configPath, "--path", targetPath]
    process.launch()
    process.waitUntilExit()

    let status = process.terminationStatus
    exit(status)

}

run(targetPath: CommandLine.arguments[1])
