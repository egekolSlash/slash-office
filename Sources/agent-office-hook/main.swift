import AgentOfficeCore
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
exit(HookCLI.run(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment, stdin: input))
