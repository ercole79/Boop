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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        #if APPSTORE
        
        checkUpdateMenuItem.isHidden = true
        
        #endif
        
        editorView.delegate = self
        
        editorView.contentTextView.selectedTextAttributes = [.backgroundColor:NSColor(red:0.19, green:0.44, blue:0.71, alpha:1.0), .foregroundColor: NSColor.white]
        
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
        let currentLength = textView.textStorage?.length ?? (textView.string as NSString).length
        let fullRange = NSRange(location: 0, length: currentLength)
        
        guard textView.shouldChangeText(in: fullRange, replacementString: newText) else {
            return
        }
        
        isApplyingStructuredFolding = true
        defer { isApplyingStructuredFolding = false }
        
        textView.textStorage?.beginEditing()
        textView.textStorage?.replaceCharacters(in: fullRange, with: newText)
        textView.textStorage?.endEditing()
        
        let newLength = textView.textStorage?.length ?? (newText as NSString).length
        let clampedLocation = max(0, min(newLength, cursorLocation))
        textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
        textView.didChangeText()
    }
}

extension MainViewController: SyntaxTextViewDelegate {
    func theme(for appearance: NSAppearance) -> SyntaxColorTheme {
        return DefaultTheme(appearance: appearance)
    }
    func didChangeText(_ syntaxTextView: SyntaxTextView) {
        guard !isApplyingStructuredFolding else {
            return
        }
        
        structuredTextFolder = nil
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
