// SPDX-License-Identifier: MPL-2.0
//
//  LunaDemoLocalFileWorkspaceAdapter.swift
//  LunaUITestApp
//
//  Demo/app-owned local filesystem adapter used for Phase 5D, 5D.1, and 5D.2.
//
//  LunaUI owns the product-neutral workspace/document contracts. This file is
//  deliberately kept in LunaUITestApp so real filesystem access, path display,
//  extension-to-syntax hints, and local save policy remain application policy
//  instead of becoming part of the reusable Luna UI library.
//

import Foundation
import LunaHostCore
import LunaUI

struct LunaDemoLaunchOptions: Hashable, Sendable {
    var mode: LunaDemoMode
    var openFilePaths: [String]
    var newUntitledDocumentCount: Int
    var createFilePaths: [String]
    var overwritesCreatedFiles: Bool
    var demoSaveAsPath: String?
    var scriptedDialogOpenPaths: [String]
    var scriptedUnsavedChangesDecision: LunaUnsavedChangesDecision?
    var usesNativeDialogs: Bool
    var overwritesSaveAsTarget: Bool
    var logsCommandRequests: Bool

    static func parse(arguments: [String], environment: [String: String]) -> LunaDemoLaunchOptions {
        var openFilePaths: [String] = []
        var createFilePaths: [String] = []
        var newUntitledDocumentCount = 0
        var demoSaveAsPath: String? = nil
        var scriptedDialogOpenPaths: [String] = []
        var scriptedUnsavedChangesDecision: LunaUnsavedChangesDecision? = nil
        var usesNativeDialogs = environment["LUNA_DEMO_NATIVE_DIALOGS"] != "0"
        var overwritesCreatedFiles = environment["LUNA_DEMO_OVERWRITE_CREATE"] == "1"
        var overwritesSaveAsTarget = environment["LUNA_DEMO_OVERWRITE_SAVE_AS"] == "1"
        let corpusRoot = environment["LUNA_DEMO_CORPUS_ROOT"] ?? "Examples/PublicDomainDemoFiles"
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                openFilePaths.append(contentsOf: arguments.dropFirst(index + 1))
                break
            } else if argument == "--open" {
                let nextIndex = index + 1
                if nextIndex < arguments.count {
                    openFilePaths.append(arguments[nextIndex])
                    index += 1
                }
            } else if argument.hasPrefix("--open=") {
                let value = String(argument.dropFirst("--open=".count))
                if !value.isEmpty { openFilePaths.append(value) }
            } else if argument == "--new" || argument == "--new-untitled" {
                newUntitledDocumentCount += 1
            } else if argument.hasPrefix("--new-untitled=") {
                let value = String(argument.dropFirst("--new-untitled=".count))
                newUntitledDocumentCount += max(1, Int(value) ?? 1)
            } else if argument == "--create" {
                let nextIndex = index + 1
                if nextIndex < arguments.count {
                    createFilePaths.append(arguments[nextIndex])
                    index += 1
                }
            } else if argument.hasPrefix("--create=") {
                let value = String(argument.dropFirst("--create=".count))
                if !value.isEmpty { createFilePaths.append(value) }
            } else if argument == "--overwrite-create" {
                overwritesCreatedFiles = true
            } else if argument == "--save-as" || argument == "--save-as-path" {
                let nextIndex = index + 1
                if nextIndex < arguments.count {
                    demoSaveAsPath = arguments[nextIndex]
                    index += 1
                }
            } else if argument.hasPrefix("--save-as=") {
                let value = String(argument.dropFirst("--save-as=".count))
                if !value.isEmpty { demoSaveAsPath = value }
            } else if argument.hasPrefix("--save-as-path=") {
                let value = String(argument.dropFirst("--save-as-path=".count))
                if !value.isEmpty { demoSaveAsPath = value }
            } else if argument == "--overwrite-save-as" {
                overwritesSaveAsTarget = true
            } else if argument == "--dialog-open" || argument == "--scripted-open" {
                let nextIndex = index + 1
                if nextIndex < arguments.count {
                    scriptedDialogOpenPaths.append(arguments[nextIndex])
                    index += 1
                }
            } else if argument.hasPrefix("--dialog-open=") {
                let value = String(argument.dropFirst("--dialog-open=".count))
                if !value.isEmpty { scriptedDialogOpenPaths.append(value) }
            } else if argument.hasPrefix("--scripted-open=") {
                let value = String(argument.dropFirst("--scripted-open=".count))
                if !value.isEmpty { scriptedDialogOpenPaths.append(value) }
            } else if argument.hasPrefix("--dialog-unsaved=") {
                let value = String(argument.dropFirst("--dialog-unsaved=".count))
                scriptedUnsavedChangesDecision = Self.unsavedDecision(value)
            } else if argument == "--no-native-dialogs" {
                usesNativeDialogs = false
            } else if argument == "--native-dialogs" {
                usesNativeDialogs = true
            } else if argument == "--open-demo-corpus" {
                openFilePaths.append(contentsOf: Self.demoCorpusFilePaths(selection: "all", root: corpusRoot))
            } else if argument.hasPrefix("--open-demo-corpus=") {
                let selection = String(argument.dropFirst("--open-demo-corpus=".count))
                openFilePaths.append(contentsOf: Self.demoCorpusFilePaths(selection: selection, root: corpusRoot))
            } else if !argument.hasPrefix("-") {
                openFilePaths.append(argument)
            }
            index += 1
        }

        if let environmentOpen = environment["LUNA_DEMO_OPEN_FILE"], !environmentOpen.isEmpty {
            openFilePaths.append(environmentOpen)
        }
        if let environmentOpenFiles = environment["LUNA_DEMO_OPEN_FILES"], !environmentOpenFiles.isEmpty {
            openFilePaths.append(contentsOf: environmentOpenFiles.split(separator: ":").map(String.init).filter { !$0.isEmpty })
        }
        if let environmentCorpus = environment["LUNA_DEMO_OPEN_CORPUS"], !environmentCorpus.isEmpty {
            openFilePaths.append(contentsOf: Self.demoCorpusFilePaths(selection: environmentCorpus, root: corpusRoot))
        }
        if let environmentNewUntitled = environment["LUNA_DEMO_NEW_UNTITLED"], !environmentNewUntitled.isEmpty {
            newUntitledDocumentCount += max(1, Int(environmentNewUntitled) ?? 1)
        }
        if let environmentCreate = environment["LUNA_DEMO_CREATE_FILE"], !environmentCreate.isEmpty {
            createFilePaths.append(environmentCreate)
        }
        if let environmentCreateFiles = environment["LUNA_DEMO_CREATE_FILES"], !environmentCreateFiles.isEmpty {
            createFilePaths.append(contentsOf: environmentCreateFiles.split(separator: ":").map(String.init).filter { !$0.isEmpty })
        }
        if let environmentSaveAsPath = environment["LUNA_DEMO_SAVE_AS_PATH"], !environmentSaveAsPath.isEmpty {
            demoSaveAsPath = environmentSaveAsPath
        }
        if let environmentDialogOpen = environment["LUNA_DEMO_DIALOG_OPEN_PATH"], !environmentDialogOpen.isEmpty {
            scriptedDialogOpenPaths.append(environmentDialogOpen)
        }
        if let environmentDialogOpenFiles = environment["LUNA_DEMO_DIALOG_OPEN_FILES"], !environmentDialogOpenFiles.isEmpty {
            scriptedDialogOpenPaths.append(contentsOf: environmentDialogOpenFiles.split(separator: ":").map(String.init).filter { !$0.isEmpty })
        }
        if let environmentUnsaved = environment["LUNA_DEMO_DIALOG_UNSAVED_DECISION"], !environmentUnsaved.isEmpty {
            scriptedUnsavedChangesDecision = Self.unsavedDecision(environmentUnsaved)
        }

        return LunaDemoLaunchOptions(
            mode: LunaDemoMode.parse(arguments: arguments, environment: environment),
            openFilePaths: Self.uniquedPreservingOrder(openFilePaths),
            newUntitledDocumentCount: newUntitledDocumentCount,
            createFilePaths: Self.uniquedPreservingOrder(createFilePaths),
            overwritesCreatedFiles: overwritesCreatedFiles,
            demoSaveAsPath: demoSaveAsPath,
            scriptedDialogOpenPaths: Self.uniquedPreservingOrder(scriptedDialogOpenPaths),
            scriptedUnsavedChangesDecision: scriptedUnsavedChangesDecision,
            usesNativeDialogs: usesNativeDialogs,
            overwritesSaveAsTarget: overwritesSaveAsTarget,
            logsCommandRequests: environment["LUNA_DEMO_DEBUG_COMMANDS"] == "1" || arguments.contains("--debug-commands")
        )
    }


    private static func unsavedDecision(_ rawValue: String) -> LunaUnsavedChangesDecision? {
        switch rawValue.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "save", "yes": return .save
        case "discard", "dont-save", "don-t-save", "no", "dontsave": return .discard
        case "cancel", "abort": return .cancel
        default: return nil
        }
    }

    private static func demoCorpusFilePaths(selection rawSelection: String, root: String) -> [String] {
        let rootURL = URL(fileURLWithPath: root, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)).standardizedFileURL
        let selection = rawSelection.lowercased().replacingOccurrences(of: "_", with: "-")

        func child(_ relativePath: String) -> String {
            rootURL.appendingPathComponent(relativePath).path
        }

        switch selection {
        case "largest", "single", "frankenstein-largest":
            return [child("frankenstein/06_final_pursuit_chapter_24.txt")]
        case "frankenstein", "mary-shelley", "shelley":
            return [
                child("frankenstein/01_walton_letter_1.txt"),
                child("frankenstein/02_victors_childhood_chapter_1.txt"),
                child("frankenstein/03_the_creation_chapter_5.txt"),
                child("frankenstein/04_mont_blanc_encounter_chapter_10.txt"),
                child("frankenstein/05_the_creature_reads_chapter_15.txt"),
                child("frankenstein/06_final_pursuit_chapter_24.txt"),
            ]
        case "caesar", "de-bello-gallico", "gallic", "latin":
            return [
                child("caesar_de_bello_gallico/01_gallia_est_omnis.txt"),
                child("caesar_de_bello_gallico/02_orgetorix_and_the_helvetii.txt"),
                child("caesar_de_bello_gallico/03_caesar_blocks_the_route.txt"),
                child("caesar_de_bello_gallico/04_battle_at_the_arar.txt"),
                child("caesar_de_bello_gallico/05_battle_near_bibracte.txt"),
                child("caesar_de_bello_gallico/06_crossing_to_britain.txt"),
            ]
        case "readme", "manifest":
            return [child("README.md")]
        case "all", "public-domain", "public-domain-demo-files", "demo", "corpus":
            return demoCorpusFilePaths(selection: "frankenstein", root: root) + demoCorpusFilePaths(selection: "caesar", root: root)
        default:
            return demoCorpusFilePaths(selection: "all", root: root)
        }
    }

    private static func uniquedPreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                output.append(value)
            }
        }
        return output
    }
}

struct LunaDemoLocalFileRegistration: Hashable, Sendable {
    var descriptor: LunaFileDescriptor?
    var statusMessage: String

    var didRegister: Bool { descriptor != nil }
}

struct LunaCPUDemoWorkspaceAdapter: LunaWorkspaceAdapter {
    var snapshot: LunaProjectTreeSnapshot
    var filesByID: [LunaFileID: LunaFileDescriptor]
    var textsByFileID: [LunaFileID: String]
    var localPathsByFileID: [LunaFileID: String]

    init(
        snapshot: LunaProjectTreeSnapshot,
        files: [LunaFileDescriptor],
        texts: [LunaFileID: String],
        localPathsByFileID: [LunaFileID: String] = [:]
    ) {
        self.snapshot = snapshot
        self.filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        self.textsByFileID = texts
        self.localPathsByFileID = localPathsByFileID
    }

    static var demo: LunaCPUDemoWorkspaceAdapter {
        LunaCPUDemoWorkspaceAdapter(
            snapshot: LunaCPUDemoScene.demoWorkspaceSnapshot,
            files: LunaCPUDemoScene.demoWorkspaceFiles,
            texts: [
                "overview": LunaCPUDemoScene.demoOverviewText,
                "editor": LunaCPUDemoScene.demoText,
                "theme": LunaCPUDemoScene.demoThemeDocumentText,
                "document-buffer": LunaCPUDemoScene.demoGeneratedWorkspaceText(title: "LunaDocumentBuffer.swift", phase: "Phase 5A", focus: "document identity and editable buffer state"),
                "editor-shell": LunaCPUDemoScene.demoGeneratedWorkspaceText(title: "LunaEditorShell.swift", phase: "Phase 4D", focus: "tabs, sidebar, status bar, and content-frame layout"),
                "completion-popup": LunaCPUDemoScene.demoGeneratedWorkspaceText(title: "LunaCompletionPopup.swift", phase: "Phase 4F", focus: "anchored completion list behavior"),
                "phase5a-tests": LunaCPUDemoScene.demoGeneratedWorkspaceText(title: "LunaUIPhase5ATests.swift", phase: "Phase 5A", focus: "document-store routing tests"),
                "roadmap": LunaCPUDemoScene.demoGeneratedWorkspaceText(title: "LUNA_UI_ROADMAP.md", phase: "Phase 5C", focus: "file/project adapter boundary"),
            ]
        )
    }

    mutating func registerLocalFiles(_ paths: [String], currentDirectory: String = FileManager.default.currentDirectoryPath) -> [LunaDemoLocalFileRegistration] {
        var registrations: [LunaDemoLocalFileRegistration] = []
        for path in paths {
            registrations.append(registerLocalFile(path, currentDirectory: currentDirectory))
        }
        rebuildLocalProjectTree()
        return registrations
    }

    mutating func createEmptyLocalFiles(
        _ paths: [String],
        overwrite: Bool = false,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> [LunaDemoLocalFileRegistration] {
        var registrations: [LunaDemoLocalFileRegistration] = []
        for path in paths {
            registrations.append(createEmptyLocalFile(path, overwrite: overwrite, currentDirectory: currentDirectory))
        }
        rebuildLocalProjectTree()
        return registrations
    }

    mutating func saveDocumentAsLocalFile(
        _ request: LunaDocumentSaveRequest,
        targetPath: String,
        overwrite: Bool = false,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> LunaDocumentSaveResult {
        let targetURL = Self.canonicalFileURL(for: targetPath, currentDirectory: currentDirectory)
        let canonicalPath = targetURL.path
        let displayPath = Self.displayPath(for: canonicalPath, currentDirectory: currentDirectory)
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: canonicalPath, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            return LunaDocumentSaveResult(outcome: .failed, documentID: request.documentID, statusMessage: "Phase 5D.2 Save As failed: target is a directory (\(displayPath))")
        }
        guard overwrite || !exists else {
            return LunaDocumentSaveResult(outcome: .failed, documentID: request.documentID, statusMessage: "Phase 5D.2 Save As refused to overwrite existing file: \(displayPath)")
        }
        let parentURL = targetURL.deletingLastPathComponent()
        var parentIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: parentURL.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            return LunaDocumentSaveResult(outcome: .failed, documentID: request.documentID, statusMessage: "Phase 5D.2 Save As failed: parent folder does not exist for \(displayPath)")
        }
        do {
            try request.text.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            return LunaDocumentSaveResult(outcome: .failed, documentID: request.documentID, statusMessage: "Phase 5D.2 Save As could not write \(displayPath): \(error.localizedDescription)")
        }
        let descriptor = localDescriptor(for: targetURL, currentDirectory: currentDirectory, phase: "5D.2")
        filesByID[descriptor.id] = descriptor
        localPathsByFileID[descriptor.id] = canonicalPath
        rebuildLocalProjectTree()
        return .saved(request, file: descriptor, statusMessage: "Phase 5D.2 saved \(request.title) as \(descriptor.displayPath)")
    }

    mutating func projectTreeSnapshot() -> LunaProjectTreeSnapshot {
        snapshot
    }

    mutating func openFile(_ request: LunaWorkspaceOpenRequest) -> LunaWorkspaceOpenResult {
        if let localPath = localPathsByFileID[request.fileID] {
            guard let file = filesByID[request.fileID] else {
                return LunaWorkspaceOpenResult(statusMessage: "Phase 5D local descriptor missing for \(request.fileID.rawValue)")
            }
            do {
                let text = try String(contentsOfFile: localPath, encoding: .utf8)
                return LunaWorkspaceOpenResult(file: file, text: text, statusMessage: "Phase 5D opened local file \(file.displayPath)")
            } catch {
                return LunaWorkspaceOpenResult(statusMessage: "Phase 5D could not read \(file.displayPath): \(error.localizedDescription)")
            }
        }

        guard let file = filesByID[request.fileID], let text = textsByFileID[request.fileID] else {
            return LunaWorkspaceOpenResult(statusMessage: "Workspace file not found: \(request.fileID.rawValue)")
        }
        return LunaWorkspaceOpenResult(file: file, text: text, statusMessage: "Phase 5D opened in-memory workspace fixture \(file.title)")
    }

    mutating func saveDocument(_ request: LunaDocumentSaveRequest) -> LunaDocumentSaveResult {
        guard let fileID = request.fileID, let file = filesByID[fileID] else {
            return LunaDocumentSaveResult(outcome: .noDestination, documentID: request.documentID, statusMessage: "Phase 5D save needs a destination for \(request.title)")
        }

        if let localPath = localPathsByFileID[fileID] {
            guard !file.isReadOnly else {
                return LunaDocumentSaveResult(outcome: .failed, documentID: request.documentID, file: file, statusMessage: "Phase 5D save failed: \(file.displayPath) is read-only")
            }
            do {
                try request.text.write(toFile: localPath, atomically: true, encoding: .utf8)
                return .saved(request, file: file, statusMessage: "Phase 5D saved local file \(file.displayPath)")
            } catch {
                return LunaDocumentSaveResult(outcome: .failed, documentID: request.documentID, file: file, statusMessage: "Phase 5D could not save \(file.displayPath): \(error.localizedDescription)")
            }
        }

        textsByFileID[fileID] = request.text
        return .saved(request, file: file, statusMessage: "Phase 5D saved in-memory workspace fixture \(request.title)")
    }

    private mutating func registerLocalFile(_ path: String, currentDirectory: String) -> LunaDemoLocalFileRegistration {
        let url = Self.canonicalFileURL(for: path, currentDirectory: currentDirectory)
        let canonicalPath = url.path
        let displayPath = Self.displayPath(for: canonicalPath, currentDirectory: currentDirectory)
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: canonicalPath, isDirectory: &isDirectory) else {
            return LunaDemoLocalFileRegistration(descriptor: nil, statusMessage: "Phase 5D local file not found: \(displayPath)")
        }
        guard !isDirectory.boolValue else {
            return LunaDemoLocalFileRegistration(descriptor: nil, statusMessage: "Phase 5D cannot open directory as text file: \(displayPath)")
        }

        if let existingID = localPathsByFileID.first(where: { $0.value == canonicalPath })?.key,
           let existing = filesByID[existingID] {
            return LunaDemoLocalFileRegistration(descriptor: existing, statusMessage: "Phase 5D local file already registered: \(existing.displayPath)")
        }

        let descriptor = localDescriptor(for: url, currentDirectory: currentDirectory, phase: "5D")
        filesByID[descriptor.id] = descriptor
        localPathsByFileID[descriptor.id] = canonicalPath
        return LunaDemoLocalFileRegistration(descriptor: descriptor, statusMessage: "Phase 5D registered local file \(displayPath)")
    }

    private mutating func createEmptyLocalFile(_ path: String, overwrite: Bool, currentDirectory: String) -> LunaDemoLocalFileRegistration {
        let url = Self.canonicalFileURL(for: path, currentDirectory: currentDirectory)
        let canonicalPath = url.path
        let displayPath = Self.displayPath(for: canonicalPath, currentDirectory: currentDirectory)
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: canonicalPath, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            return LunaDemoLocalFileRegistration(descriptor: nil, statusMessage: "Phase 5D.2 cannot create text file over directory: \(displayPath)")
        }
        guard overwrite || !exists else {
            return LunaDemoLocalFileRegistration(descriptor: nil, statusMessage: "Phase 5D.2 refused to overwrite existing file: \(displayPath)")
        }
        let parentURL = url.deletingLastPathComponent()
        var parentIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: parentURL.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            return LunaDemoLocalFileRegistration(descriptor: nil, statusMessage: "Phase 5D.2 cannot create \(displayPath): parent folder does not exist")
        }
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return LunaDemoLocalFileRegistration(descriptor: nil, statusMessage: "Phase 5D.2 could not create \(displayPath): \(error.localizedDescription)")
        }
        let descriptor = localDescriptor(for: url, currentDirectory: currentDirectory, phase: "5D.2")
        filesByID[descriptor.id] = descriptor
        localPathsByFileID[descriptor.id] = canonicalPath
        return LunaDemoLocalFileRegistration(descriptor: descriptor, statusMessage: "Phase 5D.2 created empty local file \(descriptor.displayPath)")
    }

    private func localDescriptor(for url: URL, currentDirectory: String, phase: String) -> LunaFileDescriptor {
        let canonicalPath = url.standardizedFileURL.path
        let displayPath = Self.displayPath(for: canonicalPath, currentDirectory: currentDirectory)
        let fileName = url.lastPathComponent.isEmpty ? displayPath : url.lastPathComponent
        return LunaFileDescriptor(
            id: Self.localFileID(for: canonicalPath),
            path: canonicalPath,
            displayPath: displayPath,
            name: fileName,
            projectID: Self.localProjectID,
            syntaxName: Self.syntaxName(forPathExtension: url.pathExtension),
            isReadOnly: !FileManager.default.isWritableFile(atPath: canonicalPath),
            isUntitled: false,
            metadata: [
                "adapter": "local-file",
                "local.path": canonicalPath,
                "phase": phase,
            ]
        )
    }

    private mutating func rebuildLocalProjectTree() {
        let localFiles = localPathsByFileID.keys.compactMap { filesByID[$0] }.sorted { $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending }
        var projects = snapshot.projects.filter { $0.id != Self.localProjectID }
        var roots = snapshot.roots.filter { $0.id != Self.localRootNodeID }
        guard !localFiles.isEmpty else {
            snapshot = LunaProjectTreeSnapshot(projects: projects, roots: roots, version: snapshot.version + 1)
            return
        }

        projects.append(LunaProjectDescriptor(id: Self.localProjectID, title: "Local Files", rootPath: FileManager.default.currentDirectoryPath, metadata: ["phase": "5D"]))
        let children = localFiles.map { file in
            LunaProjectTreeNode.file(
                id: LunaWorkspaceNodeID(rawValue: "local.node.\(file.id.rawValue)"),
                title: file.title,
                fileID: file.id,
                projectID: Self.localProjectID,
                subtitle: file.displayPath
            )
        }
        roots.append(.project(id: Self.localRootNodeID, title: "Local Files", projectID: Self.localProjectID, children: children))
        snapshot = LunaProjectTreeSnapshot(projects: projects, roots: roots, version: snapshot.version + 1)
    }

    private static let localProjectID = LunaProjectID(rawValue: "local-files")
    private static let localRootNodeID = LunaWorkspaceNodeID(rawValue: "local-files.root")

    private static func canonicalFileURL(for path: String, currentDirectory: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentDirectory, isDirectory: true)).standardizedFileURL
    }

    private static func displayPath(for canonicalPath: String, currentDirectory: String) -> String {
        let cwd = URL(fileURLWithPath: currentDirectory, isDirectory: true).standardizedFileURL.path
        let normalizedCWD = cwd.hasSuffix("/") ? cwd : cwd + "/"
        if canonicalPath.hasPrefix(normalizedCWD) {
            return String(canonicalPath.dropFirst(normalizedCWD.count))
        }
        return canonicalPath
    }

    private static func localFileID(for canonicalPath: String) -> LunaFileID {
        let url = URL(fileURLWithPath: canonicalPath)
        let stem = sanitizedIdentifierStem(url.deletingPathExtension().lastPathComponent)
        let hash = fnv1a64Hex(canonicalPath)
        return LunaFileID(rawValue: "local.\(stem).\(hash)")
    }

    private static func sanitizedIdentifierStem(_ value: String) -> String {
        var output = ""
        var previousWasDash = false
        for scalar in value.lowercased().unicodeScalars {
            let isAllowed = CharacterSet.alphanumerics.contains(scalar)
            if isAllowed {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                output.append("-")
                previousWasDash = true
            }
        }
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "file" : trimmed
    }

    private static func fnv1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let raw = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - raw.count)) + raw
    }

    private static func syntaxName(forPathExtension pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "swift": return "Swift"
        case "md", "markdown": return "Markdown"
        case "json": return "JSON"
        case "c", "h": return "C"
        case "cpp", "cc", "cxx", "hpp", "hh": return "C++"
        case "py": return "Python"
        case "rs": return "Rust"
        case "js", "mjs", "cjs": return "JavaScript"
        case "ts": return "TypeScript"
        case "html", "htm": return "HTML"
        case "css": return "CSS"
        case "sh", "bash", "zsh": return "Shell"
        case "txt", "text": return "Plain Text"
        default: return "Plain Text"
        }
    }
}
