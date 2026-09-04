//
//  MainViewController.swift
//  Boop
//
//  Created by Ivan on 1/26/19.
//  Copyright © 2019 OKatBest. All rights reserved.
//

import Cocoa
import SavannaKit

class MainViewController: NSViewController {

    @IBOutlet weak var editorView: SyntaxTextView!
    @IBOutlet weak var updateBuddy: UpdateBuddy!
    @IBOutlet weak var checkUpdateMenuItem: NSMenuItem!
    
    private var structuredTextFolder: StructuredTextFolder?
    private var isApplyingStructuredFolding = false
    private var lineNumberRulerView: LineNumberRulerView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        #if APPSTORE
        
        checkUpdateMenuItem.isHidden = true
        
        #endif
        
        editorView.delegate = self
        
        editorView.contentTextView.selectedTextAttributes = [.backgroundColor:NSColor(red:0.19, green:0.44, blue:0.71, alpha:1.0), .foregroundColor: NSColor.white]
        
        installLineNumberRuler()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        installLineNumberRuler()
        view.window?.makeFirstResponder(editorView.contentTextView)
    }
    
    private func installLineNumberRuler() {
        let textView = editorView.contentTextView
        let scrollView = editorView.scrollView
        
        if lineNumberRulerView == nil {
            lineNumberRulerView = LineNumberRulerView(textView: textView)
            lineNumberRulerView?.foldDelegate = self
        }
        
        scrollView.verticalRulerView = lineNumberRulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView?.clipsToBounds = true
        scrollView.tile()
    }
    @IBAction func openHelp(_ sender: Any) {
        open(url: "https://boop.okat.best/docs/")
    }
    
    
    @IBAction func openScripts(_ sender: Any) {
        open(url: "https://boop.okat.best/scripts/")
    }
    
    
    func open(url: String) {
        guard let url = URL(string: url) else {
            assertionFailure("Could not generate help URL.")
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    @IBAction func clear(_ sender: Any) {
        let textView = editorView.contentTextView
        textView.textStorage?.beginEditing()
        
        let range = NSRange(location: 0, length: textView.textStorage?.length ?? textView.string.count)
        
        guard textView.shouldChangeText(in: range, replacementString: "") else {
            return
        }
        
        textView.textStorage?.replaceCharacters(in: range, with: "")
        
        textView.textStorage?.endEditing()
        textView.didChangeText()
    }
    
    
    @IBAction func checkForUpdates(_ sender: Any) {
        updateBuddy.check()
    }
    
    @IBAction func toggleStructuredNode(_ sender: Any) {
        guard synchronizeStructuredFoldingState() else {
            NSSound.beep()
            return
        }
        
        guard let folder = structuredTextFolder else {
            NSSound.beep()
            return
        }
        
        let displayOffset = selectedRange().location
        let sourceOffset = folder.mapDisplayOffsetToSource(displayOffset)
        
        guard folder.toggleNode(atDisplayOffset: displayOffset) else {
            NSSound.beep()
            return
        }
        
        let newDisplayOffset = folder.mapSourceOffsetToDisplay(sourceOffset)
        applyStructuredText(folder.currentDisplayText, cursorLocation: newDisplayOffset)
    }
    
    @IBAction func collapseAllStructuredNodes(_ sender: Any) {
        guard synchronizeStructuredFoldingState(), let folder = structuredTextFolder else {
            NSSound.beep()
            return
        }
        
        let sourceOffset = folder.mapDisplayOffsetToSource(selectedRange().location)
        folder.collapseAll()
        let newDisplayOffset = folder.mapSourceOffsetToDisplay(sourceOffset)
        applyStructuredText(folder.currentDisplayText, cursorLocation: newDisplayOffset)
    }
    
    @IBAction func expandAllStructuredNodes(_ sender: Any) {
        guard synchronizeStructuredFoldingState(), let folder = structuredTextFolder else {
            NSSound.beep()
            return
        }
        
        let sourceOffset = folder.mapDisplayOffsetToSource(selectedRange().location)
        folder.expandAll()
        let newDisplayOffset = folder.mapSourceOffsetToDisplay(sourceOffset)
        applyStructuredText(folder.currentDisplayText, cursorLocation: newDisplayOffset)
    }
    
    private func selectedRange() -> NSRange {
        return (editorView.contentTextView.selectedRanges.first as? NSRange) ?? NSRange(location: 0, length: 0)
    }
    
    private func synchronizeStructuredFoldingState() -> Bool {
        let editorText = editorView.text
        
        if let folder = structuredTextFolder, folder.currentDisplayText != editorText {
            structuredTextFolder = nil
        }
        
        if structuredTextFolder == nil {
            structuredTextFolder = StructuredTextFolder(text: editorText)
        }
        
        return structuredTextFolder?.hasNodes == true
    }
    
    private func applyStructuredText(_ newText: String, cursorLocation: Int) {
        let textView = editorView.contentTextView
        
        isApplyingStructuredFolding = true
        defer { isApplyingStructuredFolding = false }
        
        // Use SyntaxTextView.text so lexer/layout/ruler stay consistent.
        editorView.text = newText
        
        let newLength = (newText as NSString).length
        let clampedLocation = max(0, min(newLength, cursorLocation))
        textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
        lineNumberRulerView?.needsDisplay = true
        view.window?.makeFirstResponder(textView)
    }
}

extension MainViewController: SyntaxTextViewDelegate {
    func theme(for appearance: NSAppearance) -> SyntaxColorTheme {
        return DefaultTheme(appearance: appearance)
    }
    func didChangeText(_ syntaxTextView: SyntaxTextView) {
        guard !isApplyingStructuredFolding else {
            lineNumberRulerView?.needsDisplay = true
            return
        }
        
        structuredTextFolder = StructuredTextFolder(text: syntaxTextView.text)
        if editorView.scrollView.verticalRulerView !== lineNumberRulerView {
            installLineNumberRuler()
        }
        editorView.scrollView.hasVerticalRuler = true
        editorView.scrollView.rulersVisible = true
        lineNumberRulerView?.needsDisplay = true
    }
    
    func didChangeSelectedRange(_ syntaxTextView: SyntaxTextView, selectedRange: NSRange) {
        
    }
    
    func didChangeFont(_ font: Font) {
        //
    }
    
    func lexerForSource(_ source: String) -> Lexer {
        return BoopLexer()
    }
    
    
}

extension MainViewController: LineNumberRulerViewDelegate {
    func foldMarkers(for ruler: LineNumberRulerView) -> [FoldMarker] {
        if structuredTextFolder == nil {
            structuredTextFolder = StructuredTextFolder(text: editorView.text)
        }
        return structuredTextFolder?.foldMarkers() ?? []
    }
    
    func lineNumberRulerView(_ ruler: LineNumberRulerView, didToggleFoldMarker marker: FoldMarker) {
        guard synchronizeStructuredFoldingState(), let folder = structuredTextFolder else {
            NSSound.beep()
            return
        }
        
        let sourceOffset = folder.mapDisplayOffsetToSource(selectedRange().location)
        guard folder.toggleNode(id: marker.nodeID) else {
            NSSound.beep()
            return
        }
        
        let newDisplayOffset = folder.mapSourceOffsetToDisplay(sourceOffset)
        applyStructuredText(folder.currentDisplayText, cursorLocation: newDisplayOffset)
    }
}
