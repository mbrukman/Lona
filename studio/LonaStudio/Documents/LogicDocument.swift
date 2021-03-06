//
//  LogicDocument.swift
//  LonaStudio
//
//  Created by Devin Abbott on 6/5/19.
//  Copyright © 2019 Devin Abbott. All rights reserved.
//

import AppKit
import Logic

class LogicDocument: BaseDocument {

    override init() {
        super.init()

        self.hasUndoManager = true
    }

    override var autosavingFileType: String? {
        return nil
    }

    var viewController: WorkspaceViewController? {
        return windowControllers[0].contentViewController as? WorkspaceViewController
    }

    var content: LGCSyntaxNode = .topLevelDeclarations(
        .init(
            id: UUID(),
            declarations: .init([.makePlaceholder()])
        )
    ) {
        didSet {
            if let url = fileURL {
                LogicModule.invalidateCaches(url: url, newValue: program)
            }
        }
    }

    var program: LGCProgram {
        return LGCProgram.make(from: content)!
    }

    public static func encode(_ content: LGCSyntaxNode) throws -> Data {
        let encoder = JSONEncoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData = try encoder.encode(content)

        if let xmlData = LogicFile.convert(jsonData, kind: .logic, to: .source) {
            return xmlData
        } else {
            Swift.print("Failed to save logic file as source")
            return jsonData
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        return try LogicDocument.encode(content)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        content = try LogicDocument.read(from: fileURL!)
    }

    private static func read(from data: Data) throws -> LGCSyntaxNode {
        guard let jsonData = LogicFile.convert(data, kind: .logic, to: .json) else {
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, userInfo: nil)
        }

        let decoded = try JSONDecoder().decode(LGCSyntaxNode.self, from: jsonData)

        // Normalize the imported data
        // TODO: Figure out why multiple placeholders are loaded
        let content = decoded.replace(id: UUID(), with: .literal(.boolean(id: UUID(), value: true)))

        return content

    }

    public static func read(from url: URL) throws -> LGCSyntaxNode {
        let data = try Data(contentsOf: url)

        let content = try read(from: data)

        if let cached = readCache[url], cached.isEquivalentTo(content) {
            return cached
        } else {
            readCache[url] = content

            return content
        }
    }

    private static var readCache: [URL: LGCSyntaxNode] = [:]

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        let dataOnDisk = try? Data(contentsOf: url)

        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)

        let newData = try? self.data(ofType: typeName)

        // only invalidate if what was on the disk is different from what we saved
        if dataOnDisk != newData {
          LogicModule.invalidateCaches(url: url, newValue: program)
        }
    }
}
