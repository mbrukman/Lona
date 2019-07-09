//
//  LogicViewController.swift
//  LonaStudio
//
//  Created by Devin Abbott on 6/5/19.
//  Copyright © 2019 Devin Abbott. All rights reserved.
//

import AppKit
import Logic

// MARK: - LogicViewController

class LogicViewController: NSViewController {

    // MARK: Lifecycle

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)

        setUpViews()
        setUpConstraints()

        update()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        setUpViews()
        setUpConstraints()

        update()
    }

    // MARK: Public

    public var rootNode: LGCSyntaxNode = .topLevelDeclarations(
        .init(
            id: UUID(),
            declarations: .init([.makePlaceholder()])
        )
    ) { didSet { update() } }

    public var onChangeRootNode: ((LGCSyntaxNode) -> Void)?

    // MARK: Private

    private let logicEditor = LogicEditor()
    private let infoBar = InfoBar()
    private let divider = Divider()
    private let containerView = NSBox()

    private var colorValues: [UUID: String] = [:]

    private let editorDisplayStyles: [LogicFormattingOptions.Style] = [.visual, .natural]

    private func setUpViews() {
        containerView.boxType = .custom
        containerView.borderType = .noBorder
        containerView.contentViewMargins = .zero

        containerView.addSubview(logicEditor)
        containerView.addSubview(infoBar)
        containerView.addSubview(divider)

        infoBar.fillColor = Colors.contentBackground

        divider.fillColor = NSSplitView.defaultDividerColor

        logicEditor.fillColor = Colors.contentBackground
        logicEditor.canvasStyle.textMargin = .init(width: 10, height: 6)
        logicEditor.showsFilterBar = true
        logicEditor.suggestionFilter = LogicViewController.suggestionFilter

        logicEditor.onChangeSuggestionFilter = { [unowned self] value in
            self.logicEditor.suggestionFilter = value
            LogicViewController.suggestionFilter = value
        }

        logicEditor.formattingOptions = LogicFormattingOptions(
            style: LogicViewController.formattingStyle,
            getColor: { [unowned self] id in
                guard let colorString = self.colorValues[id],
                    let color = NSColor.parse(css: colorString) else { return nil }
                return (colorString, color)
            }
        )

        infoBar.dropdownIndex = editorDisplayStyles.firstIndex(of: LogicViewController.formattingStyle) ?? 0
        infoBar.dropdownValues = editorDisplayStyles.map { $0.displayName }
        infoBar.onChangeDropdownIndex = { [unowned self] index in
            LogicViewController.formattingStyle = self.editorDisplayStyles[index]
            let newFormattingOptions = self.logicEditor.formattingOptions
            newFormattingOptions.style = self.editorDisplayStyles[index]
            self.logicEditor.formattingOptions = newFormattingOptions
            self.infoBar.dropdownIndex = index
        }

        self.view = containerView
    }

    private func setUpConstraints() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        logicEditor.translatesAutoresizingMaskIntoConstraints = false
        infoBar.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false

        logicEditor.topAnchor.constraint(equalTo: containerView.topAnchor).isActive = true
        logicEditor.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
        logicEditor.trailingAnchor.constraint(equalTo: containerView.trailingAnchor).isActive = true

        logicEditor.bottomAnchor.constraint(equalTo: divider.topAnchor).isActive = true

        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        divider.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
        divider.trailingAnchor.constraint(equalTo: containerView.trailingAnchor).isActive = true

        divider.bottomAnchor.constraint(equalTo: infoBar.topAnchor).isActive = true

        infoBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor).isActive = true
        infoBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
        infoBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor).isActive = true
    }

    private static func makePreludeProgram() -> LGCProgram {
        return .init(
            id: UUID(),
            block: .init(
                [
                    .declaration(
                        id: UUID(),
                        content: .importDeclaration(id: UUID(), name: .init(id: UUID(), name: "Prelude"))
                    )
                ]
            )
        )
    }

    private func evaluate() {
        let (scopeContext, unificationContext, substitutionResult) = StandardConfiguration.compile(rootNode)

        guard let substitution = try? substitutionResult.get() else { return }

        guard let evaluationContext = try? Compiler.evaluate(
            rootNode,
            rootNode: rootNode,
            scopeContext: scopeContext,
            unificationContext: unificationContext,
            substitution: substitution,
            context: .init()
            ).get() else { return }

        evaluationContext.values.forEach { id, value in
            if let colorString = value.colorString {
                colorValues[id] = colorString
            }
        }
    }

    private func update() {
        logicEditor.rootNode = rootNode

        evaluate()

        logicEditor.onChangeRootNode = { [unowned self] newRootNode in
            self.onChangeRootNode?(newRootNode)
            return true
        }

        logicEditor.suggestionsForNode = { rootNode, node, query in
            guard let root = LGCProgram.make(from: rootNode) else { return [] }

            let program: LGCSyntaxNode = .program(
                LGCProgram.join(programs: [LogicViewController.makePreludeProgram(), root])
                    .expandImports(importLoader: Library.load)
            )

            let recommended = LogicViewController.recommendedSuggestions(rootNode: program, selectedNode: node, query: query)

            return recommended
        }

        logicEditor.decorationForNodeID = { [unowned self] id in
            guard let node = self.logicEditor.rootNode.find(id: id) else { return nil }

            if let colorValue = self.colorValues[node.uuid] {
                if self.logicEditor.formattingOptions.style == .visual,
                    let path = self.logicEditor.rootNode.pathTo(id: id),
                    let parent = path.dropLast().last {

                    // Don't show color decoration on the variable name
                    switch parent {
                    case .declaration(.variable):
                        return nil
                    default:
                        break
                    }

                    // Don't show color decoration of literal value if we're already showing a swatch preview
                    if let grandParent = path.dropLast().dropLast().last {
                        switch (grandParent, parent, node) {
                        case (.declaration(.variable), .expression(.literalExpression), .literal(.color)):
                            return nil
                        default:
                            break
                        }
                    }
                }

                return .color(NSColor.parse(css: colorValue) ?? NSColor.black)
            }

            switch node {
            case .literal(.color(id: _, value: let code)):
                return .color(NSColor.parse(css: code) ?? .clear)
            default:
                return nil
            }
        }
    }

    public static func recommendedSuggestions(rootNode: LGCSyntaxNode, selectedNode: LGCSyntaxNode, query: String) -> [LogicSuggestionItem] {
        let all = StandardConfiguration.suggestions(rootNode: rootNode, node: selectedNode, query: query)
            ?? LogicEditor.defaultSuggestionsForNode(rootNode, selectedNode, query)

        switch selectedNode {
        case .declaration:
            let variableId = UUID()
            let colorExample = LGCSyntaxNode.declaration(
                LGCDeclaration.variable(
                    id: UUID(),
                    name: LGCPattern(id: UUID(), name: "ocean"),
                    annotation: LGCTypeAnnotation.typeIdentifier(
                        id: UUID(),
                        identifier: LGCIdentifier(id: UUID(), string: "Color", isPlaceholder: false),
                        genericArguments: .empty
                    ),
                    initializer: .literalExpression(id: UUID(), literal: .color(id: UUID(), value: "#69D2E7"))
                )
            )
            let colorVariable = LogicSuggestionItem(
                title: "Color Variable",
                category: "Declarations".uppercased(),
                node: LGCSyntaxNode.declaration(
                    LGCDeclaration.variable(
                        id: UUID(),
                        name: LGCPattern(id: variableId, name: "name"),
                        annotation: LGCTypeAnnotation.typeIdentifier(
                            id: UUID(),
                            identifier: LGCIdentifier(id: UUID(), string: "Color", isPlaceholder: false),
                            genericArguments: .empty
                        ),
                        initializer: .literalExpression(id: UUID(), literal: .color(id: UUID(), value: "white"))
                    )
                ),
                suggestionFilters: [.recommended],
                nextFocusId: variableId,
                documentation: RichText(
                    blocks: [
                        .heading(.title, "Color Variable"),
                        .paragraph(
                            [
                                .text(.none, """
Define a color variable that can be used throughout your design system and UI components.

For example, we might define a variable,
"""),
                                .text(.bold, " ocean"),
                                .text(.none, ", to represent the hex code "),
                                .text(.bold, "#69D2E7"),
                                .text(.none, ":")
                            ]
                        ),
                        .custom(
                            colorExample.makeCodeView(using: .init(style: formattingStyle, locale: .en_US, getColor: { id in
                                guard let node = colorExample.find(id: id) else { return nil }
                                switch node {
                                case .expression(.literalExpression(_, literal: .color(_, value: let value))):
                                    return (value, NSColor.parse(css: value) ?? .clear)
                                default:
                                    return nil
                                }
                            }))
                        ),
                        .heading(.section, "Naming Conventions"),
                        .paragraph(
                            [
                                .text(.none, """
There are a variety of naming conventions for colors, each with their own strengths and weaknesses. For more details and recommendations on naming conventions, see
"""), .text(.link, " this documentation page.")
                            ]
                        )
                    ]
                )
            )

            let patternId = UUID()

            let namespace = LogicSuggestionItem(
                title: "Variable Group",
                category: "Declarations".uppercased(),
                node: LGCSyntaxNode.declaration(
                    LGCDeclaration.namespace(
                        id: UUID(),
                        name: LGCPattern(id: patternId, name: "name"),
                        declarations: .next(LGCDeclaration.makePlaceholder(), .empty)
                    )
                ),
                suggestionFilters: [.recommended],
                nextFocusId: patternId,
                documentation: RichText(blocks:
                    [
                        .heading(.title, "Variable Group"),
                        .paragraph(
                            [
                                .text(.none, """
A group of variables and other declarations, sometimes called a namespace.

This will generate fairly different code for each platform, so if you're curious to see what it turns into, open the split preview pane.
""")
                            ]
                        )
                    ]
                )
            )

            return [colorVariable, namespace] + all
        default:
            return all.map {
                var node = $0
                node.suggestionFilters = [.recommended, .all]
                return node
            }
        }
    }

    private static var formattingStyleKey = "Logic editor style"

    static var formattingStyle: LogicFormattingOptions.Style {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: formattingStyleKey),
                let value = LogicFormattingOptions.Style(rawValue: rawValue) else {
                return LogicFormattingOptions.Style.visual
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: formattingStyleKey)
        }
    }

    private static var suggestionFilterKey = "Logic editor suggestion filter"

    static var suggestionFilter: SuggestionView.SuggestionFilter {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: suggestionFilterKey) else {
                return .recommended
            }
            switch rawValue {
            case "all":
                return .all
            default:
                return .recommended
            }
        }
        set {
            var rawValue: String
            switch newValue {
            case .all:
                rawValue = "all"
            case .recommended:
                rawValue = "recommended"
            }
            UserDefaults.standard.set(rawValue, forKey: suggestionFilterKey)
        }
    }
}