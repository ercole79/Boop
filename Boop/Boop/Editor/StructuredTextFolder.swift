//
//  StructuredTextFolder.swift
//  Boop
//
//  Created by Cursor on 9/3/26.
//

import Foundation

enum StructuredContentKind {
    case json
    case xml
}

struct StructuredNode: Hashable {
    let id: Int
    let sourceRange: NSRange
    let summary: String
}

struct FoldMarker: Hashable {
    let nodeID: Int
    let lineNumber: Int
    let isCollapsed: Bool
}

struct StructuredDocument {
    let kind: StructuredContentKind
    let sourceText: String
    let nodes: [StructuredNode]
}

struct StructuredRenderSegment {
    let sourceRange: NSRange
    let displayRange: NSRange
    let collapsedNodeID: Int?
}

final class StructuredTextFolder {
    let document: StructuredDocument
    private(set) var collapsedNodeIDs = Set<Int>()
    private(set) var currentDisplayText: String
    private(set) var renderSegments: [StructuredRenderSegment] = []

    init?(text: String) {
        guard let document = StructuredTextFolder.parseDocument(from: text) else {
            return nil
        }
        self.document = document
        self.currentDisplayText = text
        self.renderSegments = [
            StructuredRenderSegment(
                sourceRange: NSRange(location: 0, length: (text as NSString).length),
                displayRange: NSRange(location: 0, length: (text as NSString).length),
                collapsedNodeID: nil
            )
        ]
    }

    var hasNodes: Bool {
        !document.nodes.isEmpty
    }

    func foldMarkers() -> [FoldMarker] {
        let display = currentDisplayText as NSString
        var markers: [FoldMarker] = []

        for node in document.nodes {
            if isObscuredByCollapsedAncestor(node) {
                continue
            }

            let displayOffset = mapSourceOffsetToDisplay(node.sourceRange.location)
            markers.append(
                FoldMarker(
                    nodeID: node.id,
                    lineNumber: Self.lineNumber(at: displayOffset, in: display),
                    isCollapsed: collapsedNodeIDs.contains(node.id)
                )
            )
        }

        return markers
    }

    @discardableResult
    func toggleNode(id: Int) -> Bool {
        guard document.nodes.contains(where: { $0.id == id }) else {
            return false
        }

        if collapsedNodeIDs.contains(id) {
            collapsedNodeIDs.remove(id)
        } else {
            collapsedNodeIDs.insert(id)
        }

        render()
        return true
    }

    func collapseAll() {
        collapsedNodeIDs = Set(document.nodes.map(\.id))
        render()
    }

    func expandAll() {
        collapsedNodeIDs.removeAll()
        render()
    }

    @discardableResult
    func toggleNode(atDisplayOffset displayOffset: Int) -> Bool {
        let clampedOffset = clampDisplayOffset(displayOffset)

        if let collapsedNodeID = collapsedNodeID(atDisplayOffset: clampedOffset) {
            collapsedNodeIDs.remove(collapsedNodeID)
            render()
            return true
        }

        let sourceOffset = mapDisplayOffsetToSource(clampedOffset)
        guard let node = smallestNode(containingSourceOffset: sourceOffset) else {
            return false
        }

        if collapsedNodeIDs.contains(node.id) {
            collapsedNodeIDs.remove(node.id)
        } else {
            collapsedNodeIDs.insert(node.id)
        }

        render()
        return true
    }

    func mapDisplayOffsetToSource(_ displayOffset: Int) -> Int {
        let clampedOffset = clampDisplayOffset(displayOffset)

        if renderSegments.isEmpty {
            return clampSourceOffset(clampedOffset)
        }

        for (index, segment) in renderSegments.enumerated() {
            let displayStart = segment.displayRange.location
            let displayEnd = displayStart + segment.displayRange.length
            let isLastSegment = index == renderSegments.count - 1

            if clampedOffset < displayStart {
                continue
            }

            if clampedOffset > displayEnd {
                continue
            }

            if clampedOffset == displayEnd && !isLastSegment {
                continue
            }

            let sourceStart = segment.sourceRange.location
            let sourceEnd = sourceStart + segment.sourceRange.length

            if segment.collapsedNodeID != nil {
                return clampedOffset <= displayStart ? sourceStart : sourceEnd
            }

            return sourceStart + (clampedOffset - displayStart)
        }

        return (document.sourceText as NSString).length
    }

    func mapSourceOffsetToDisplay(_ sourceOffset: Int) -> Int {
        let clampedOffset = clampSourceOffset(sourceOffset)

        if renderSegments.isEmpty {
            return clampDisplayOffset(clampedOffset)
        }

        for (index, segment) in renderSegments.enumerated() {
            let sourceStart = segment.sourceRange.location
            let sourceEnd = sourceStart + segment.sourceRange.length
            let isLastSegment = index == renderSegments.count - 1

            if clampedOffset < sourceStart {
                continue
            }

            if clampedOffset > sourceEnd {
                continue
            }

            if clampedOffset == sourceEnd && !isLastSegment {
                continue
            }

            let displayStart = segment.displayRange.location
            let displayEnd = displayStart + segment.displayRange.length

            if segment.collapsedNodeID != nil {
                return displayStart
            }

            return min(displayEnd, displayStart + (clampedOffset - sourceStart))
        }

        return (currentDisplayText as NSString).length
    }

    private func collapsedNodeID(atDisplayOffset displayOffset: Int) -> Int? {
        for segment in renderSegments {
            let start = segment.displayRange.location
            let end = start + segment.displayRange.length
            if displayOffset >= start, displayOffset < end {
                return segment.collapsedNodeID
            }
        }
        return nil
    }

    private func smallestNode(containingSourceOffset sourceOffset: Int) -> StructuredNode? {
        var bestNode: StructuredNode?

        for node in document.nodes {
            let start = node.sourceRange.location
            let end = start + node.sourceRange.length
            if sourceOffset < start || sourceOffset >= end {
                continue
            }

            if let currentBest = bestNode {
                if node.sourceRange.length < currentBest.sourceRange.length {
                    bestNode = node
                }
            } else {
                bestNode = node
            }
        }

        return bestNode
    }

    private func render() {
        let source = document.sourceText as NSString
        let sourceLength = source.length
        let collapsedNodes = visibleCollapsedNodes()

        if collapsedNodes.isEmpty {
            currentDisplayText = document.sourceText
            renderSegments = [
                StructuredRenderSegment(
                    sourceRange: NSRange(location: 0, length: sourceLength),
                    displayRange: NSRange(location: 0, length: sourceLength),
                    collapsedNodeID: nil
                )
            ]
            return
        }

        var output = ""
        var segments: [StructuredRenderSegment] = []
        var sourceCursor = 0
        var displayCursor = 0

        for node in collapsedNodes {
            let nodeStart = node.sourceRange.location
            let nodeEnd = nodeStart + node.sourceRange.length

            if nodeStart > sourceCursor {
                let plainRange = NSRange(location: sourceCursor, length: nodeStart - sourceCursor)
                let plainChunk = source.substring(with: plainRange)
                output += plainChunk
                let displayRange = NSRange(location: displayCursor, length: (plainChunk as NSString).length)
                segments.append(StructuredRenderSegment(sourceRange: plainRange, displayRange: displayRange, collapsedNodeID: nil))
                sourceCursor = nodeStart
                displayCursor += displayRange.length
            }

            output += node.summary
            let collapsedDisplayLength = (node.summary as NSString).length
            let collapsedDisplayRange = NSRange(location: displayCursor, length: collapsedDisplayLength)
            segments.append(StructuredRenderSegment(sourceRange: node.sourceRange, displayRange: collapsedDisplayRange, collapsedNodeID: node.id))
            sourceCursor = nodeEnd
            displayCursor += collapsedDisplayLength
        }

        if sourceCursor < sourceLength {
            let plainRange = NSRange(location: sourceCursor, length: sourceLength - sourceCursor)
            let plainChunk = source.substring(with: plainRange)
            output += plainChunk
            let displayRange = NSRange(location: displayCursor, length: (plainChunk as NSString).length)
            segments.append(StructuredRenderSegment(sourceRange: plainRange, displayRange: displayRange, collapsedNodeID: nil))
        }

        currentDisplayText = output
        renderSegments = segments
    }

    private func visibleCollapsedNodes() -> [StructuredNode] {
        let requestedCollapsedNodes = document.nodes
            .filter { collapsedNodeIDs.contains($0.id) }
            .sorted {
                if $0.sourceRange.location == $1.sourceRange.location {
                    return $0.sourceRange.length > $1.sourceRange.length
                }
                return $0.sourceRange.location < $1.sourceRange.location
            }

        var visibleNodes: [StructuredNode] = []
        var coveredRangeEnd = -1

        for node in requestedCollapsedNodes {
            let nodeStart = node.sourceRange.location
            let nodeEnd = nodeStart + node.sourceRange.length

            if nodeStart < coveredRangeEnd {
                continue
            }

            visibleNodes.append(node)
            coveredRangeEnd = nodeEnd
        }

        return visibleNodes
    }

    private func isObscuredByCollapsedAncestor(_ node: StructuredNode) -> Bool {
        let nodeStart = node.sourceRange.location
        let nodeEnd = nodeStart + node.sourceRange.length

        for other in document.nodes where other.id != node.id && collapsedNodeIDs.contains(other.id) {
            let otherStart = other.sourceRange.location
            let otherEnd = otherStart + other.sourceRange.length
            if nodeStart >= otherStart && nodeEnd <= otherEnd && node.sourceRange.length < other.sourceRange.length {
                return true
            }
        }

        return false
    }

    static func lineNumber(at offset: Int, in string: NSString) -> Int {
        let clamped = max(0, min(string.length, offset))
        var line = 1
        if clamped == 0 {
            return line
        }

        for index in 0..<clamped {
            let character = string.character(at: index)
            if character == 10 {
                line += 1
            } else if character == 13 {
                let next = index + 1
                if next >= clamped || string.character(at: next) != 10 {
                    line += 1
                }
            }
        }

        return line
    }

    private func clampDisplayOffset(_ offset: Int) -> Int {
        return max(0, min((currentDisplayText as NSString).length, offset))
    }

    private func clampSourceOffset(_ offset: Int) -> Int {
        return max(0, min((document.sourceText as NSString).length, offset))
    }
}

private extension StructuredTextFolder {
    static func parseDocument(from text: String) -> StructuredDocument? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let firstCharacter = trimmed.first, firstCharacter == "{" || firstCharacter == "[" {
            if let jsonDocument = parseJSONDocument(from: text) {
                return jsonDocument
            }
        }

        if trimmed.first == "<", let xmlDocument = parseXMLDocument(from: text) {
            return xmlDocument
        }

        return nil
    }

    static func parseJSONDocument(from text: String) -> StructuredDocument? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }

        guard (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else {
            return nil
        }

        let source = text as NSString
        let sourceLength = source.length
        var stack: [(character: unichar, location: Int)] = []
        var nodes: [(range: NSRange, summary: String)] = []
        var isInsideString = false
        var isEscaping = false

        for index in 0..<sourceLength {
            let character = source.character(at: index)

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                    continue
                }

                if character == 92 { // "\"
                    isEscaping = true
                    continue
                }

                if character == 34 { // """
                    isInsideString = false
                }
                continue
            }

            if character == 34 { // """
                isInsideString = true
                continue
            }

            if character == 123 || character == 91 { // "{" or "["
                stack.append((character, index))
                continue
            }

            if character == 125 || character == 93 { // "}" or "]"
                guard let open = stack.popLast() else {
                    return nil
                }

                let isMatchingPair = (open.character == 123 && character == 125) || (open.character == 91 && character == 93)
                guard isMatchingPair else {
                    return nil
                }

                let range = NSRange(location: open.location, length: index - open.location + 1)
                guard containsNewline(in: source, range: range) else {
                    continue
                }

                let openCharacter = String(UnicodeScalar(Int(open.character)) ?? "{".unicodeScalars.first!)
                let closeCharacter = String(UnicodeScalar(Int(character)) ?? "}".unicodeScalars.first!)
                let summary = "\(openCharacter) ... \(closeCharacter)"
                nodes.append((range: range, summary: summary))
            }
        }

        guard stack.isEmpty else {
            return nil
        }

        let sortedNodes = nodes
            .sorted {
                if $0.range.location == $1.range.location {
                    return $0.range.length < $1.range.length
                }
                return $0.range.location < $1.range.location
            }
            .enumerated()
            .map { index, node in
                StructuredNode(id: index, sourceRange: node.range, summary: node.summary)
            }

        guard !sortedNodes.isEmpty else {
            return nil
        }

        return StructuredDocument(kind: .json, sourceText: text, nodes: sortedNodes)
    }

    static func parseXMLDocument(from text: String) -> StructuredDocument? {
        let source = text as NSString
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return nil
        }

        let fullRange = NSRange(location: 0, length: source.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        var stack: [(name: String, range: NSRange, token: String)] = []
        var nodes: [(range: NSRange, summary: String)] = []

        for match in matches {
            let tokenRange = match.range
            let token = source.substring(with: tokenRange)
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedToken.hasPrefix("<?") || trimmedToken.hasPrefix("<!") || trimmedToken.hasPrefix("<!--") {
                continue
            }

            if trimmedToken.hasPrefix("</") {
                guard let closingName = xmlTagName(in: trimmedToken, isClosingTag: true) else {
                    return nil
                }

                guard let openTag = stack.popLast(), openTag.name == closingName else {
                    return nil
                }

                let location = openTag.range.location
                let length = tokenRange.location + tokenRange.length - location
                let range = NSRange(location: location, length: length)

                guard containsNewline(in: source, range: range) else {
                    continue
                }

                let summary = "\(openTag.token) ... \(trimmedToken)"
                nodes.append((range: range, summary: summary))
                continue
            }

            if trimmedToken.hasSuffix("/>") {
                continue
            }

            guard let name = xmlTagName(in: trimmedToken, isClosingTag: false) else {
                return nil
            }

            stack.append((name: name, range: tokenRange, token: trimmedToken))
        }

        guard stack.isEmpty else {
            return nil
        }

        let sortedNodes = nodes
            .sorted {
                if $0.range.location == $1.range.location {
                    return $0.range.length < $1.range.length
                }
                return $0.range.location < $1.range.location
            }
            .enumerated()
            .map { index, node in
                StructuredNode(id: index, sourceRange: node.range, summary: node.summary)
            }

        guard !sortedNodes.isEmpty else {
            return nil
        }

        return StructuredDocument(kind: .xml, sourceText: text, nodes: sortedNodes)
    }

    static func xmlTagName(in token: String, isClosingTag: Bool) -> String? {
        let prefixLength = isClosingTag ? 2 : 1
        guard token.count > prefixLength else {
            return nil
        }

        let startIndex = token.index(token.startIndex, offsetBy: prefixLength)
        var endIndex = startIndex

        while endIndex < token.endIndex {
            let character = token[endIndex]
            if character == ">" || character == "/" || character == " " || character == "\t" || character == "\n" || character == "\r" {
                break
            }
            endIndex = token.index(after: endIndex)
        }

        guard startIndex < endIndex else {
            return nil
        }

        return String(token[startIndex..<endIndex])
    }

    static func containsNewline(in source: NSString, range: NSRange) -> Bool {
        let end = range.location + range.length
        guard range.location >= 0, range.length >= 0, end <= source.length else {
            return false
        }

        for index in range.location..<end {
            let character = source.character(at: index)
            if character == 10 || character == 13 {
                return true
            }
        }
        return false
    }
}
