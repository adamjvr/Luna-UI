// SPDX-License-Identifier: MPL-2.0
//
//  LunaDemoNativeDialogService.swift
//  LunaUITestApp
//
//  Demo/app-owned native dialog bridge for Phase 5D.3.
//
//  This intentionally lives in the test app target, not LunaUI. LunaUI owns
//  product-neutral document/workspace state. The app/host owns native Open,
//  Save As, and unsaved-changes UI. This file uses a scripted layer for tests
//  and repeatable CLI demos, then desktop helpers for interactive Linux/macOS
//  runs when available.
//
//  Future Plan-B seam:
//  An in-Luna file-browser widget can also satisfy LunaDialogService later. The
//  editor command path will not need to know whether a path came from AppKit,
//  XDG Portal, zenity/kdialog, Win32, or a Luna-rendered file browser.

import Foundation
import LunaHostCore

struct LunaDemoNativeDialogService: LunaDialogService {
    var scripted: LunaScriptedDialogService
    var desktop: LunaDesktopDialogProvider
    var prefersDesktopDialogs: Bool

    var providerDescription: String {
        if scripted.hasScriptedOpenSelection || scripted.hasScriptedSaveSelection || scripted.hasScriptedUnsavedDecision {
            return "scripted + \(desktop.providerDescription)"
        }
        return prefersDesktopDialogs ? desktop.providerDescription : scripted.providerDescription
    }

    init(
        scripted: LunaScriptedDialogService = LunaScriptedDialogService(),
        desktop: LunaDesktopDialogProvider = LunaDesktopDialogProvider(),
        prefersDesktopDialogs: Bool = true
    ) {
        self.scripted = scripted
        self.desktop = desktop
        self.prefersDesktopDialogs = prefersDesktopDialogs
    }

    mutating func confirmUnsavedChanges(_ request: LunaUnsavedChangesDialogRequest) -> LunaUnsavedChangesDialogResult {
        if scripted.hasScriptedUnsavedDecision {
            return scripted.confirmUnsavedChanges(request)
        }
        if prefersDesktopDialogs {
            let result = desktop.confirmUnsavedChanges(request)
            if result.statusMessage?.contains("unavailable") != true {
                return result
            }
        }
        return scripted.confirmUnsavedChanges(request)
    }

    mutating func chooseFileToOpen(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        if scripted.hasScriptedOpenSelection {
            return scripted.chooseFileToOpen(request)
        }
        if prefersDesktopDialogs {
            let result = desktop.chooseFileToOpen(request)
            if result.outcome != .unavailable {
                return result
            }
        }
        return scripted.chooseFileToOpen(request)
    }

    mutating func chooseFileToSave(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        if scripted.hasScriptedSaveSelection {
            return scripted.chooseFileToSave(request)
        }
        if prefersDesktopDialogs {
            let result = desktop.chooseFileToSave(request)
            if result.outcome != .unavailable {
                return result
            }
        }
        return scripted.chooseFileToSave(request)
    }
}

struct LunaDesktopDialogProvider: Hashable, Sendable {
    var environment: [String: String]
    var currentDirectory: String

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) {
        self.environment = environment
        self.currentDirectory = currentDirectory
    }

    var providerDescription: String {
        #if os(macOS)
        return "AppKit/AppleScript desktop dialogs"
        #elseif os(Linux)
        if let helper = selectedLinuxDialogHelperName() {
            return "Linux desktop dialogs via \(helper)"
        }
        return "Linux desktop dialogs unavailable"
        #else
        return "desktop dialogs unavailable on this platform"
        #endif
    }

    func confirmUnsavedChanges(_ request: LunaUnsavedChangesDialogRequest) -> LunaUnsavedChangesDialogResult {
        #if os(macOS)
        return confirmUnsavedChangesWithAppleScript(request)
        #elseif os(Linux)
        return confirmUnsavedChangesWithLinuxHelper(request)
        #else
        return .cancel("Native unsaved-changes dialog unavailable on this platform")
        #endif
    }

    func chooseFileToOpen(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        #if os(macOS)
        return chooseFileToOpenWithAppleScript(request)
        #elseif os(Linux)
        return chooseFileToOpenWithLinuxHelper(request)
        #else
        return .unavailable("Native Open… dialog unavailable on this platform", providerName: providerDescription)
        #endif
    }

    func chooseFileToSave(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        #if os(macOS)
        return chooseFileToSaveWithAppleScript(request)
        #elseif os(Linux)
        return chooseFileToSaveWithLinuxHelper(request)
        #else
        return .unavailable("Native Save As… dialog unavailable on this platform", providerName: providerDescription)
        #endif
    }

    // MARK: - Linux helpers

    #if os(Linux)
    private enum LinuxDialogHelper: String {
        case zenity
        case yad
        case kdialog
    }

    private func selectedLinuxDialogHelperName() -> String? {
        selectedLinuxDialogHelper()?.rawValue
    }

    private func selectedLinuxDialogHelper() -> LinuxDialogHelper? {
        if let forced = environment["LUNA_DEMO_DIALOG_HELPER"]?.lowercased(), !forced.isEmpty {
            return LinuxDialogHelper(rawValue: forced).flatMap { commandExists($0.rawValue) ? $0 : nil }
        }
        for helper in [LinuxDialogHelper.zenity, .yad, .kdialog] {
            if commandExists(helper.rawValue) { return helper }
        }
        return nil
    }

    private func confirmUnsavedChangesWithLinuxHelper(_ request: LunaUnsavedChangesDialogRequest) -> LunaUnsavedChangesDialogResult {
        guard let helper = selectedLinuxDialogHelper() else {
            return .cancel("Native dirty-close dialog unavailable; install zenity, yad, kdialog, or use scripted dialog env vars")
        }
        let title = "Save Changes?"
        let text = "Save changes to \(request.title) before closing?"
        switch helper {
        case .zenity, .yad:
            let completed = runProcess(
                helper.rawValue,
                arguments: [
                    "--question",
                    "--title=\(title)",
                    "--text=\(text)",
                    "--ok-label=Save",
                    "--cancel-label=Cancel",
                    "--extra-button=Don't Save",
                ]
            )
            let output = completed.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if output == "Don't Save" {
                return .discard("Dirty-close dialog: Don't Save selected for \(request.title)")
            }
            if completed.exitCode == 0 {
                return .save("Dirty-close dialog: Save selected for \(request.title)")
            }
            return .cancel("Dirty-close dialog cancelled for \(request.title)")

        case .kdialog:
            let completed = runProcess(
                helper.rawValue,
                arguments: [
                    "--title", title,
                    "--warningyesnocancel", text,
                    "--yes-label", "Save",
                    "--no-label", "Don't Save",
                    "--cancel-label", "Cancel",
                ]
            )
            switch completed.exitCode {
            case 0:
                return .save("Dirty-close dialog: Save selected for \(request.title)")
            case 1:
                return .discard("Dirty-close dialog: Don't Save selected for \(request.title)")
            default:
                return .cancel("Dirty-close dialog cancelled for \(request.title)")
            }
        }
    }

    private func chooseFileToOpenWithLinuxHelper(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        guard let helper = selectedLinuxDialogHelper() else {
            return .unavailable("Native Open… dialog unavailable; install zenity, yad, kdialog, or use --open/scripted paths", providerName: providerDescription)
        }
        switch helper {
        case .zenity, .yad:
            var args = ["--file-selection", "--title=\(request.title)"]
            if request.allowsMultipleSelection {
                args.append("--multiple")
                args.append("--separator=\n")
            }
            if let directory = request.defaultDirectory, !directory.isEmpty {
                args.append("--filename=\(directory.hasSuffix("/") ? directory : directory + "/")")
            }
            let completed = runProcess(helper.rawValue, arguments: args)
            guard completed.exitCode == 0 else {
                return .cancelled("Open… dialog cancelled", providerName: helper.rawValue)
            }
            let paths = splitDialogPathOutput(completed.stdout)
            return paths.isEmpty
                ? .cancelled("Open… dialog returned no path", providerName: helper.rawValue)
                : .selected(paths, providerName: helper.rawValue, statusMessage: "Open… selected \(paths.count) path(s)")

        case .kdialog:
            var args = ["--getopenfilename"]
            args.append(request.defaultDirectory ?? currentDirectory)
            let completed = runProcess(helper.rawValue, arguments: args)
            guard completed.exitCode == 0 else {
                return .cancelled("Open… dialog cancelled", providerName: helper.rawValue)
            }
            let paths = splitDialogPathOutput(completed.stdout)
            return paths.isEmpty
                ? .cancelled("Open… dialog returned no path", providerName: helper.rawValue)
                : .selected(paths, providerName: helper.rawValue, statusMessage: "Open… selected \(paths.count) path(s)")
        }
    }

    private func chooseFileToSaveWithLinuxHelper(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        guard let helper = selectedLinuxDialogHelper() else {
            return .unavailable("Native Save As… dialog unavailable; install zenity, yad, kdialog, or use --save-as/scripted paths", providerName: providerDescription)
        }
        let defaultPath = defaultSavePath(for: request)
        switch helper {
        case .zenity, .yad:
            let completed = runProcess(
                helper.rawValue,
                arguments: [
                    "--file-selection",
                    "--save",
                    "--confirm-overwrite",
                    "--title=\(request.title)",
                    "--filename=\(defaultPath)",
                ]
            )
            guard completed.exitCode == 0 else {
                return .cancelled("Save As… dialog cancelled", providerName: helper.rawValue)
            }
            let paths = splitDialogPathOutput(completed.stdout)
            return paths.first.map {
                .selected([$0], allowsOverwrite: true, providerName: helper.rawValue, statusMessage: "Save As… selected \($0)")
            } ?? .cancelled("Save As… dialog returned no path", providerName: helper.rawValue)

        case .kdialog:
            let completed = runProcess(
                helper.rawValue,
                arguments: ["--getsavefilename", defaultPath]
            )
            guard completed.exitCode == 0 else {
                return .cancelled("Save As… dialog cancelled", providerName: helper.rawValue)
            }
            let paths = splitDialogPathOutput(completed.stdout)
            return paths.first.map {
                .selected([$0], allowsOverwrite: true, providerName: helper.rawValue, statusMessage: "Save As… selected \($0)")
            } ?? .cancelled("Save As… dialog returned no path", providerName: helper.rawValue)
        }
    }
    #endif

    // MARK: - macOS AppleScript helpers

    #if os(macOS)
    private func confirmUnsavedChangesWithAppleScript(_ request: LunaUnsavedChangesDialogRequest) -> LunaUnsavedChangesDialogResult {
        let script = """
        set dialogResult to display dialog \(appleScriptString("Save changes to \(request.title) before closing?")) buttons {\"Cancel\", \"Don't Save\", \"Save\"} default button \"Save\" cancel button \"Cancel\" with title \"Save Changes?\"
        return button returned of dialogResult
        """
        let completed = runProcess("/usr/bin/osascript", arguments: ["-e", script])
        let output = completed.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output == "Save" { return .save("Dirty-close dialog: Save selected for \(request.title)") }
        if output == "Don't Save" { return .discard("Dirty-close dialog: Don't Save selected for \(request.title)") }
        return .cancel("Dirty-close dialog cancelled for \(request.title)")
    }

    private func chooseFileToOpenWithAppleScript(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        let script = """
        set chosenFile to choose file with prompt \(appleScriptString(request.title))
        return POSIX path of chosenFile
        """
        let completed = runProcess("/usr/bin/osascript", arguments: ["-e", script])
        guard completed.exitCode == 0 else {
            return .cancelled("Open… dialog cancelled", providerName: "osascript")
        }
        let paths = splitDialogPathOutput(completed.stdout)
        return paths.isEmpty
            ? .cancelled("Open… dialog returned no path", providerName: "osascript")
            : .selected(paths, providerName: "osascript", statusMessage: "Open… selected \(paths.count) path(s)")
    }

    private func chooseFileToSaveWithAppleScript(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        let defaultName = request.defaultFileName ?? "Untitled.txt"
        let script = """
        set chosenFile to choose file name with prompt \(appleScriptString(request.title)) default name \(appleScriptString(defaultName))
        return POSIX path of chosenFile
        """
        let completed = runProcess("/usr/bin/osascript", arguments: ["-e", script])
        guard completed.exitCode == 0 else {
            return .cancelled("Save As… dialog cancelled", providerName: "osascript")
        }
        let paths = splitDialogPathOutput(completed.stdout)
        return paths.first.map {
            .selected([$0], allowsOverwrite: true, providerName: "osascript", statusMessage: "Save As… selected \($0)")
        } ?? .cancelled("Save As… dialog returned no path", providerName: "osascript")
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    #endif

    // MARK: - Shared helpers

    private func defaultSavePath(for request: LunaFileDialogRequest) -> String {
        let directory = request.defaultDirectory?.isEmpty == false ? request.defaultDirectory! : currentDirectory
        let filename = request.defaultFileName?.isEmpty == false ? request.defaultFileName! : "Untitled.txt"
        return URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(filename).path
    }

    private func splitDialogPathOutput(_ output: String) -> [String] {
        output
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func commandExists(_ name: String) -> Bool {
        let completed = runProcess("/usr/bin/env", arguments: ["sh", "-lc", "command -v \(shellQuoted(name)) >/dev/null 2>&1"])
        return completed.exitCode == 0
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runProcess(_ executable: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = executable.hasPrefix("/")
            ? URL(fileURLWithPath: executable)
            : URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = executable.hasPrefix("/") ? arguments : [executable] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        } catch {
            return ProcessResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
        }
    }
}

private struct ProcessResult: Hashable, Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

extension LunaDemoLaunchOptions {
    var dialogService: LunaDemoNativeDialogService {
        var unsavedDecisions: [LunaUnsavedChangesDecision] = []
        if let scripted = scriptedUnsavedChangesDecision {
            unsavedDecisions.append(scripted)
        }

        var saveSelections: [String] = []
        if let demoSaveAsPath {
            saveSelections.append(demoSaveAsPath)
        }

        let scripted = LunaScriptedDialogService(
            providerDescription: "scripted LunaUITestApp dialog service",
            unsavedDecisions: unsavedDecisions,
            openPathSelections: scriptedDialogOpenPaths.map { [$0] },
            savePathSelections: saveSelections,
            scriptedSelectionsAllowOverwrite: overwritesSaveAsTarget,
            fallback: LunaNoOpDialogService(providerDescription: "no scripted LunaUITestApp dialog response")
        )
        return LunaDemoNativeDialogService(
            scripted: scripted,
            desktop: LunaDesktopDialogProvider(environment: ProcessInfo.processInfo.environment),
            prefersDesktopDialogs: usesNativeDialogs
        )
    }
}
