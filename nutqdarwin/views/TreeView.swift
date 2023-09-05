//
//  TreeView.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 7/3/23.
//

import SwiftUI
import Combine


extension NSAttributedString.Key {
    static let index = NSAttributedString.Key("scheme_index")
}

fileprivate let indentWidth: CGFloat = 15
fileprivate let hangingIndent: CGFloat = 15
fileprivate let timeHeight: CGFloat = 13
fileprivate let timeOffset: CGFloat = 0

#if os(macOS)
typealias NativeColor = NSColor
#else
typealias NativeColor = UIColor
#endif

fileprivate let backgroundColor = NativeColor(red: 0.841, green: 0.888, blue: 0.888, alpha: 1)
#if os(iOS)
fileprivate let textAttributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: NativeColor.systemIndigo.withAlphaComponent(0.7),
    .backgroundColor: backgroundColor
]
#else
fileprivate let textAttributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: NativeColor.systemIndigo.withAlphaComponent(0.7),
]
#endif

fileprivate let mainHeight: CGFloat = {
    return NSString("0").size().height
}()

#if os(macOS)
fileprivate let buttonRect = CGRect(x: -15, y: mainHeight / 2 - 7, width: 14, height: 14)
#else
fileprivate let buttonRect = CGRect(x: -15, y: -mainHeight / 2 - 7, width: 14, height: 14)
#endif

// rect relative to the line, last parameter is total width
fileprivate func width(for scheme: SchemeItem) -> (NSAttributedString, CGRect) {
    var string = ""
    if let start = scheme.start {
        string += start.dateString
        string += " \u{2192}"
    }
    if let end = scheme.end {
        if string.count == 0 {
            string += "\u{2192} " + end.dateString
        }
        else {
            string += " " + (end.dayDifference(with: scheme.start!) == 0 ? end.timeString :  end.dateString)
        }
    }
    
    switch scheme.repeats {
    case.none:
        break
    case .block:
        string += " block"
    }
    
    let nsString = NSAttributedString(string: string, attributes: textAttributes)
    let size = nsString.size()
    let containerWidth = size.width
    #warning("TODO, forgot why this even works on macos??")
    #if os(macOS)
    let rect = CGRect(x: -containerWidth / 2 + size.width / 2 + timeOffset, y: -size.height, width: size.width, height: size.height)
    #else
    let rect = CGRect(x: -containerWidth / 2 + size.width / 2 + timeOffset, y: 0, width: size.width, height: size.height)
    #endif
    
    return (nsString, rect)
}

#if os(macOS)
extension NSImage {
    func tint(color: NSColor) -> NSImage {
        return NSImage(size: size, flipped: false) { (rect) -> Bool in
            color.set()
            rect.fill()
            self.draw(in: rect, from: NSRect(origin: .zero, size: self.size), operation: .destinationIn, fraction: 1.0)
            return true
        }
    }
}

final class TreeTextView: NSTextView, NSTextStorageDelegate {
    var schemes: Binding<[SchemeItem]>!
    var handles: [AnyCancellable] = []
    var gutterView: GutterView!
    var addNewLineFlag = false
    var initialFocused = false
    var pipe: AnyCancellable!
    var deleteRange: Range<Int>?
    
    var sr: NSRange {
        get { self.selectedRange() }
        set { self.setSelectedRange(newValue)}
    }
    var ts: NSTextStorage { self.textStorage! }
    var text: String { self.string }

    static func factory(schemes: Binding<[SchemeItem]>) -> TreeTextView {
        let ret = TreeTextView()
        ret.schemes = schemes
        ret.gutterView = GutterView(schemes: schemes, layoutManager: ret.layoutManager!, textStorage: ret.textStorage!)
        ret.addSubview(ret.gutterView)
        
        ret.handles = schemes.map { ret.subscriber(for: $0.wrappedValue ) }
        
        ret.allowsUndo = true
        
        ret.autoresizingMask = .width
        
        ret.backgroundColor = .clear
        ret.insertionPointColor = .black

        ret.textColor = .black
        ret.selectedTextAttributes = [.backgroundColor: NSColor(red: 0.98, green: 0.89, blue: 0.67, alpha: 1)]

        ret.isAutomaticSpellingCorrectionEnabled = false
        ret.isAutomaticTextReplacementEnabled = false
        ret.isAutomaticTextCompletionEnabled = false
        ret.isAutomaticQuoteSubstitutionEnabled = false
        ret.isAutomaticDashSubstitutionEnabled = false
        ret.isAutomaticLinkDetectionEnabled = false
        ret.isAutomaticDataDetectionEnabled = false
        ret.textStorage?.delegate = ret
        
        return ret
    }
    
    override func insertNewline(_ sender: Any?) {
        self.breakUndoCoalescing()
        
        super.insertNewline(sender)
        
        self.breakUndoCoalescing()
    }

    override func insertTab(_ sender: Any?) {
        self.tab(delta: 1)
    }

    override func insertBacktab(_ sender: Any?) {
        self.tab(delta: -1)
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func didChangeText() {
        super.didChangeText()

        let history = !(self.undoManager?.isUndoing ?? false) && !(self.undoManager?.isRedoing ?? false)
        if (addNewLineFlag || !string.hasSuffix("\n")) && history  {
            addNewLineFlag = false

            self.addAuxiliaryLine()
        }
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        self.preFixSchemes(range: affectedCharRange)
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        // ensure scheme ids are consistent
        self.fixSchemes(range: editedRange)
        self.gutterView.needsLayout = true
    }
    
    override func layout() {
        super.layout()

        self.gutterView.layout()
    }
    
    override func mouseDown(with event: NSEvent) {
        if !self.gutterView.handleClick(with: event) {
            super.mouseDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
        if !initialFocused {
            self.scrollRangeToVisible(self.selectedRange())
            initialFocused = true
        }
        return true
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
        self.handles = []
        self.pipe.cancel()
        initialFocused = false
    }
}

class ItemButton: NSButton {
    @Binding var schemeState: [Int]
    var imageName: String?
    
    init(schemeState: Binding<[Int]>) {
        self._schemeState = schemeState
        super.init(frame: .zero)
        
        self.imageScaling = .scaleProportionallyUpOrDown
        self.bezelStyle = .texturedSquare
        self.isBordered = false
        self.isEnabled = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(_ box: NSRect) {
        self.frame = box
        self.needsDisplay = true
        
        let imageName = schemeState.allSatisfy { $0 == -1 } ? "checkmark.square" : (schemeState.count > 1 ? "dot.square" : "square")
        
        if imageName != self.imageName {
            self.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)?
                .tint(color: NSColor(red: CGFloat(11 / 255.0), green: CGFloat(79 / 255.0), blue: CGFloat(121 / 255.0), alpha: 1))
            self.imageName = imageName
        }
    }
    
//    override func resetCursorRects() {
//        super.resetCursorRects()
//
//        addCursorRect(bounds, cursor: .pointingHand)
//    }
   
    // not sure why this needs to be done in the first place?
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self.bounds.contains(point) ? self : nil
    }
    
    func toggle() {
        if schemeState.count == 1 {
            schemeState[0] = -1 - schemeState[0]
            self.update(self.frame)
        }
    }
}

class ItemLabel: NSView {
    private var string: NSAttributedString = NSAttributedString(string: "")
    
    override func draw(_ dirtyRect: NSRect) {
        let rect = self.convert(self.frame, from: self.superview)
        string.draw(in: rect)
    }
    
    func update(_ box: NSRect, _ label: NSAttributedString) {
        self.frame = box
        self.string = label
        self.needsDisplay = true
    }
}

// terribly inefficient, but whatever
class GutterView: NSView {
    @Binding var schemes: [SchemeItem]
    
    /* covers up highlights as well as has necessary buttons for completion, etc */
    unowned let layoutManager: NSLayoutManager
    unowned let textStorage: NSTextStorage
    
    var buttons: [ItemButton] = []
    var labels: [ItemLabel] = []
    
    init(schemes: Binding<[SchemeItem]>, layoutManager: NSLayoutManager, textStorage: NSTextStorage) {
        self._schemes = schemes
        self.layoutManager = layoutManager
        self.textStorage = textStorage
        super.init(frame: .zero)
        
        self.autoresizingMask = [.width, .height]
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func convert(_ rect: NSRect) -> NSRect {
        self.convert(rect, from: self.superview!)
    }
    
    func convert(_ point: NSPoint) -> NSPoint {
        self.convert(point, from: self.superview!)
    }
    
    override func layout() {
        self.needsDisplay = true
        
        self.reallyLayout()
    }
    
    func handleClick(with event: NSEvent) -> Bool {
        if let view = self.hitTest(convert(event.locationInWindow, from: nil)) as? ItemButton {
            view.toggle()
            return true
        }
        
        return false
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in self.buttons {
            if let ret = subview.hitTest(convert(point, to: subview)) {
                return ret
            }
        }
        
        return nil
    }
    
    func setNeedsLayout() {
        self.needsLayout = true
    }
    
    func setNeedsDisplay() {
        self.needsDisplay = true
    }
}

class TouchThroughScrollView: NSScrollView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInView = convert(point, to: documentView)
        
        // If the point is inside the document view, return true to pass the event through
        if documentView?.frame.contains(pointInView) ?? false {
            return documentView
        }
        
        return super.hitTest(point)
    }
}

struct TreeNativeView: NSViewRepresentable {
    // we want to be notified of changes to specific schemes, but not insertions or deletions
    @ObservedObject var scheme: SchemeItemList
    let menu: MenuState
    let scrollCounter: Int

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSScrollView {
        let scroll = TouchThroughScrollView()
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalRuler  = false
        scroll.backgroundColor = backgroundColor
        
        let ret = TreeTextView.factory(schemes: $scheme.schemes)
        ret.listen(to: menu)
        
        self.attribute(ret)
        
        scroll.documentView = ret
        ret.scrollToEndOfDocument(nil)
        
        return scroll
    }
    
    func attribute(_ document: TreeTextView) {
        let string = NSMutableAttributedString()
        for (i, scheme) in scheme.schemes.enumerated() {
            let currString = scheme.text + "\n"
            string.append(NSAttributedString(string: currString, attributes: [.index: i]))
        }
       
        document.textStorage?.setAttributedString(string)
        document.applyInitialAttributes() // refresh paragraph style
    }
    
    func updateNSView(_ nsView: NSScrollView, context: NSViewRepresentableContext<Self>) { }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator { }
}
#else

final class TreeTextView: UITextView, NSTextStorageDelegate, UITextViewDelegate {
    var schemes: Binding<[SchemeItem]>!
    var handles: [AnyCancellable] = []
    var gutterView: GutterView!
    var addNewLineFlag = false
    var pipe: AnyCancellable!
    var deleteRange: NSRange?
    
    var sr: NSRange {
        get { self.selectedRange }
        set { selectedRange = newValue }
    }
    var ts: NSTextStorage { self.textStorage }

    static func factory(schemes: Binding<[SchemeItem]>) -> TreeTextView {
        let ret = TreeTextView()
        ret.schemes = schemes
        ret.gutterView = GutterView(schemes: schemes, layoutManager: ret.layoutManager, textStorage: ret.textStorage)
        ret.addSubview(ret.gutterView)
        
        ret.handles = schemes.map { ret.subscriber(for: $0.wrappedValue ) }
        
        ret.backgroundColor = .clear
        ret.textColor = .black

        ret.textStorage.delegate = ret
        ret.delegate = ret
        
        return ret
    }
    
    func convert(_ range: UITextRange) -> NSRange {
        let startOffset = self.offset(from: self.beginningOfDocument, to: range.start)
        let endOffset = self.offset(from: self.beginningOfDocument, to: range.end)
           
        return NSRange(location: startOffset, length: endOffset - startOffset)
    }

    func textViewDidChange(_ textView: UITextView) {
        if addNewLineFlag || !text.hasSuffix("\n") {
            addNewLineFlag = false
            
            let old = self.sr
            self.ts.append(NSAttributedString(string: "\n"))
            sr = old
        }
    }

    override func shouldChangeText(in affectedCharRange: UITextRange, replacementText replacementString: String) -> Bool {
        self.preFixSchemes(range: self.convert(affectedCharRange))
        return super.shouldChangeText(in: affectedCharRange, replacementText: replacementString)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {
        // ensure scheme ids are consistent
        self.fixSchemes(range: editedRange)
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
        self.handles = []
        self.pipe.cancel()
    }
}

class ItemLabel: UIView {
    private var string: NSAttributedString = NSAttributedString(string: "")
    
    
    override func draw(_ dirtyRect: CGRect) {
        let rect = self.convert(self.frame, from: self.superview)
        string.draw(in: rect)
    }
    
    func update(_ box: CGRect, _ label: NSAttributedString) {
        self.frame = box
        self.string = label
        self.setNeedsDisplay()
    }
}

class ItemButton: UIButton {
    @Binding var schemeState: [Int]
    var imageName: String?
    
    init(schemeState: Binding<[Int]>) {
        self._schemeState = schemeState
        super.init(frame: .zero)
        
        self.isEnabled = true
        self.addTarget(self, action: #selector(ItemButton.toggle), for: .touchUpInside)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(_ box: CGRect) {
        self.frame = box
        self.setNeedsDisplay()
        
        let imageName = schemeState.allSatisfy { $0 == -1 } ? "checkmark.square" : (schemeState.count > 1 ? "dot.square" : "square")
        
        if imageName != self.imageName {
            self.setImage(UIImage(systemName: imageName)?
                .withTintColor(UIColor(red: CGFloat(11 / 255.0), green: CGFloat(79 / 255.0), blue: CGFloat(121 / 255.0), alpha: 1), renderingMode: .alwaysOriginal), for: .normal)
            self.imageName = imageName
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return self.bounds.contains(point) ? self : nil
    }
    
    @objc
    func toggle() {
        if schemeState.count == 1 {
            schemeState[0] = -1 - schemeState[0]
            self.update(self.frame)
        }
    }
}

class GutterView: UIView {
    @Binding var schemes: [SchemeItem]
    
    /* covers up highlights as well as has necessary buttons for completion, etc */
    unowned let layoutManager: NSLayoutManager
    unowned let textStorage: NSTextStorage
    
    var buttons: [ItemButton] = []
    var labels: [ItemLabel] = []
    
    init(schemes: Binding<[SchemeItem]>, layoutManager: NSLayoutManager, textStorage: NSTextStorage) {
        self._schemes = schemes
        self.layoutManager = layoutManager
        self.textStorage = textStorage
        super.init(frame: .zero)
        
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func convert(_ rect: CGRect) -> CGRect {
        self.convert(rect, from: self.superview!)
    }
    
    func convert(_ point: CGPoint) -> CGPoint {
        self.convert(point, from: self.superview!)
    }
    
    override func layoutSubviews() {
        self.reallyLayout()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in self.buttons {
            if let ret = subview.hitTest(convert(point, to: subview), with: event) {
                return ret
            }
        }
        
        return nil
    }
}

struct TreeNativeView: UIViewRepresentable {
    // we want to be notified of changes to specific schemes, but not insertions or deletions
    @ObservedObject var scheme: SchemeItemList
    let menu: MenuState
    let scrollCounter: Int

    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIScrollView {
        let ret = TreeTextView.factory(schemes: $scheme.schemes)
        ret.backgroundColor = backgroundColor
        ret.listen(to: menu)
        ret.textContainerInset = .zero
        
        self.attribute(ret)
        
        return ret
    }
    
    func attribute(_ document: TreeTextView) {
        let string = NSMutableAttributedString()
        for (i, scheme) in scheme.schemes.enumerated() {
            let currString = scheme.text + "\n"
            string.append(NSAttributedString(string: currString, attributes: [.index: i]))
        }
       
        document.ts.setAttributedString(string)
        document.applyInitialAttributes() // refresh paragraph style
    }
    
    func updateUIView(_ nsView: UIScrollView, context: UIViewRepresentableContext<Self>) { }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator { }
}

#endif

struct TreeView: View {
    // we want to be notified of changes to specific schemes, but not insertions or deletions
    let scheme: SchemeItemList
    let menu: MenuState
    
    @State var counter = 0
    @FocusState var focused
   
    var body: some View {
        TreeNativeView(scheme: scheme, menu: menu, scrollCounter: counter)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color(red: 0.841, green: 0.888, blue: 0.888))
        #if os(macOS)
            .padding(.bottom, 75)
            .background(.ultraThickMaterial)
        #endif
            .focused($focused)
            .onAppear {
                focused = true
            }
            .onChange(of: scheme.id) {
                focused = true
            }
    }
}


extension TreeTextView {
   
    func subscriber(for scheme: SchemeItem) -> AnyCancellable {
        var enabled = false
        let ret = scheme.statePublisher.receive(on: RunLoop.main).sink { _ in
            if enabled {
                let (ranges, _) = self.lines(startIndex: 0)[self.schemes.wrappedValue.firstIndex(of: scheme)!]
                self.applyDerivedStyles(range: ranges)
            }
        }
        
        enabled = true
        
        return ret
    }
    
    func listen(to publisher: MenuState) {
        self.pipe = publisher.sink { action in
            #if os(macOS)
            if self.window?.firstResponder != self {
                return
            }
            #else
            if !self.isFirstResponder {
                return
            }
            #endif
            
            switch action {
            case .toggle:
                self.ts.enumerateAttribute(.index, in: self.lineRange()) { value, range, _ in
                    guard let index = value as? Int else {
                        return
                    }
                    
                    if self.schemes.wrappedValue[index].state.count == 1 {
                        self.schemes.wrappedValue[index].state[0] = -1 - self.schemes.wrappedValue[index].state[0]
                    }
                }
            case .toggleStartView:
                break;
            case .toggleEndView:
                break;
            case .toggleBlockView:
                break;
            case .disableStart:
                break;
            case .disableEnd:
                break
            case .disableBlock:
                break
            default:
                break
            }
        }
    }
    
    func lineRange() -> NSRange {
        let range = self.sr
        let str = ts.string
        let start = str.index(str.startIndex, offsetBy: range.location)
        let end   = str.index(start, offsetBy: range.length)
        let fullRange = str.lineRange(for: start ..< end)
        let nsRange = NSRange(location: str.distance(from: str.startIndex, to: fullRange.lowerBound), length: str.distance(from: fullRange.lowerBound, to: fullRange.upperBound))
        
        return nsRange
    }
    
    func tab(delta: Int) {
        if self.sr.location == text.count {
            self.addAuxiliaryLine()
        }
        
        ts.enumerateAttribute(.index, in: self.lineRange()) { value, range, _ in
            let attrs = ts.attributes(at: range.location, effectiveRange: nil)
            
            guard let index = value as? Int , let style = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else {
                return
            }
            
            let indentation = schemes[index].indentation
            indentation.wrappedValue = max(0, indentation.wrappedValue + delta)
            
            style.firstLineHeadIndent = indentWidth * CGFloat(indentation.wrappedValue)
            style.headIndent = style.firstLineHeadIndent
            style.firstLineHeadIndent += hangingIndent
            
            ts.addAttribute(.paragraphStyle, value: style, range: range)
        }
        
        gutterView.setNeedsLayout()
    }
    
    func applyDerivedStyles(range: NSRange) {
        guard let index = ts.attributes(at: range.location, effectiveRange: nil)[.index] as? Int else {
            return
        }
        
        let scheme = schemes[index].wrappedValue
        
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indentWidth * CGFloat(scheme.indentation)
        style.headIndent = style.firstLineHeadIndent
        style.firstLineHeadIndent += hangingIndent
        
        if scheme.start != nil || scheme.end != nil || scheme.repeats != .none {
            style.paragraphSpacing = timeHeight
        }
        
        ts.addAttribute(.paragraphStyle, value: style, range: range)
        
        if scheme.state.allSatisfy({ $0 == -1 }) {
            ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            ts.addAttribute(.foregroundColor, value: NativeColor.black.withAlphaComponent(0.6), range: range)
            ts.addAttribute(.strikethroughColor, value: NativeColor.black.withAlphaComponent(0.3), range: range)
        }
        else {
            ts.addAttribute(.foregroundColor, value: NativeColor.black, range: range)
            ts.removeAttribute(.strikethroughStyle, range: range)
            ts.removeAttribute(.strikethroughColor, range: range)
        }
    }
    
    func preFixSchemes(range: NSRange) {
        guard range.length != 0 else {
            return
        }
        
        var preLines = range.location == 0 ? 1 : 1 + (self.ts.attributes(at: range.location - 1, effectiveRange: nil)[.index] as? Int ?? 0)
        
        if range.location > 0 && text[text.index(text.startIndex, offsetBy: range.location - 1)] == "\n" {
            preLines += 1
        }

        let subRanges = self.lines(startIndex: range.upperBound)
        let k: Int = subRanges.count + preLines - 1
       
        let history = !(self.undoManager?.isUndoing ?? false) && !(self.undoManager?.isRedoing ?? false)
        if k < schemes.count && history {
            let firstIndex = 1 + (ts.attributes(at: range.lowerBound, effectiveRange: nil)[.index] as! Int)
            var lastIndex = ts.attributes(at: range.upperBound - 1, effectiveRange: nil)[.index] as! Int
            
            if text[text.index(text.startIndex, offsetBy: range.upperBound - 1)] == "\n" {
                lastIndex += 1
            }
            
            if lastIndex == schemes.count {
                lastIndex -= 1
                addNewLineFlag = true
            }
           
            if firstIndex <= lastIndex  {
                deleteRange = firstIndex ..< lastIndex + 1
            }
        }
        
        gutterView.setNeedsLayout()
    }
    
    func addAuxiliaryLine() {
        let old = self.selectedRange()
        self.ts.append(NSAttributedString(string: "\n"))
        self.setSelectedRange(old)
        self.addNewLineFlag = false
        
        self.undoManager?.registerUndo(withTarget: self) {
            $0.removeAuxiliaryLine()
        }
        
        print("Add Schemes: ", self.schemes.count, "Handles", self.handles.count, "Lines", self.lines(startIndex: 0).count)
    }
    
    func removeAuxiliaryLine() {
        let old = self.selectedRange()
        self.string.removeLast()
        self.setSelectedRange(old)
        
        self.undoManager?.registerUndo(withTarget: self) {
            $0.addAuxiliaryLine()
        }
        
        print("Remove Schemes: ", self.schemes.count, "Handles", self.handles.count, "Lines", self.lines(startIndex: 0).count)
    }
    
    func delete(range: Range<Int>) {
        let items = Array(schemes.wrappedValue[range])
        self.schemes.wrappedValue.removeSubrange(range)
        self.handles.removeSubrange(range)
        
        self.undoManager?.registerUndo(withTarget: self) {
            $0.insert(items: items, at: range.lowerBound)
            $0.gutterView.setNeedsLayout()
        }
        
        print("Delete Schemes: ", self.schemes.count, "Handles", self.handles.count, "Lines", self.lines(startIndex: 0).count)
    }
        
    func insert(items: [SchemeItem], at index: Int) {
        self.schemes.wrappedValue.insert(contentsOf: items, at: index)
        handles.insert(contentsOf: items.map {
            self.subscriber(for: $0)
        }, at: index)
        
        self.undoManager?.registerUndo(withTarget: self) {
            $0.delete(range: index ..< index + items.count)
            $0.gutterView.setNeedsLayout()
        }
        
        print("Insert Schemes: ", self.schemes.count, "Handles", self.handles.count, "Lines", self.lines(startIndex: 0).count)
    }
    
    // not perfect, but generally does what we want
    func fixSchemes(range: NSRange) {
        let pastIndex = range.location == 0 ? -1 : self.ts.attributes(at: range.location - 1, effectiveRange: nil)[.index] as? Int ?? -1
        
        // this is wrong
        let subRanges = self.lines(startIndex: range.location)
        
        let prev = subRanges.count > 0 && subRanges[0].0.location < range.location ? pastIndex : pastIndex + 1
        var k = prev
        
        for (subRange, _) in subRanges {
            self.ts.addAttribute(.index, value: k, range: subRange)
            k += 1
        }
        
        if let range = self.deleteRange {
            self.delete(range: range)
            deleteRange = nil
        }
        
        if k > self.schemes.count {
            // similary insert at the current point if there's deltas
            let index: Int
            let aux: [SchemeItem]
            if pastIndex == -1 {
                aux = (0 ..< k - self.schemes.count).map { _ in
                    blankEditor("", indentation: self.schemes.wrappedValue[0].indentation)
                }
                
                index = pastIndex + 2
            }
            else if pastIndex < schemes.count - 1 && text[text.index(text.startIndex, offsetBy: range.location - 1)] == "\n" {
                aux = (0 ..< k - self.schemes.count).map { _ in
                    blankEditor("", indentation: self.schemes.wrappedValue[pastIndex + 1].indentation)
                }
                
                index = pastIndex + 2
            }
            else {
                aux = (0 ..< k - self.schemes.count).map { _ in
                    blankEditor("", indentation: self.schemes.wrappedValue[pastIndex].indentation)
                }
                
                index = pastIndex + 1
            }
            
            if Float.random(in: 0...1) < 0.5 {
                aux[0].start = .now
            }
           
            self.insert(items: aux, at: index)
        }

        // update relevant text...
        k = prev
        for (subRange, stringRange) in subRanges {
            self.applyDerivedStyles(range: subRange)
            
            let str = text[stringRange.lowerBound ..< text.index(before: stringRange.upperBound)]
            self.schemes[k].wrappedValue.text = String(str)
            
            k += 1
            
            if subRange.lowerBound > range.upperBound {
                break
            }
        }
    
        gutterView.setNeedsLayout()
        print("Fix Schemes: ", self.schemes.count, "Handles", self.handles.count, "Lines", self.lines(startIndex: 0).count)
    }
    
    func applyInitialAttributes() {
        for (subRange, _) in self.lines(startIndex: 0) {
            applyDerivedStyles(range: subRange)
        }
    }
    
    func lines(startIndex: Int) -> [(NSRange, Range<String.Index>)] {
        let str: String! = text
        var it = str.index(str.startIndex, offsetBy: startIndex)
        var oldEnd: Int! = nil
        
        var ret: [(NSRange, Range<String.Index>)] = []
        
        while it != str.endIndex {
            let range = str.lineRange(for: it ... it)
            let distance = str.distance(from: range.lowerBound, to: range.upperBound)
            
            if oldEnd == nil {
                let start = str.distance(from: str.startIndex, to: range.lowerBound)
                oldEnd = start
            }
            
            ret.append((NSRange(location: oldEnd, length: distance), range))
           
            oldEnd += distance
            it = range.upperBound
        }
        
        return ret
    }
}

extension GutterView {
    func reallyLayout() {
        self.setNeedsDisplay()
        
        var encountered = 0
        textStorage.enumerateAttribute(.index, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let id = value as? Int else {
                return
            }
            
            let scheme = schemes[id]
            
            let xRange = self.layoutManager.glyphRange(forCharacterRange: NSRange(location: range.lowerBound, length: 0), actualCharacterRange: nil)
            let yRange = self.layoutManager.glyphRange(forCharacterRange: NSRange(location: range.upperBound - 1, length: 0), actualCharacterRange: nil)
            
            let xRect = layoutManager.boundingRect(forGlyphRange: xRange, in: self.layoutManager.textContainers[0])
            let yRect = layoutManager.boundingRect(forGlyphRange: yRange, in: self.layoutManager.textContainers[0])
            
            var yStart = yRect.origin
            yStart.y += yRect.height
            
            var xStart = xRect.origin
            xStart.y += xRect.height
            
            let convX = self.convert(xStart)
            let convY = self.convert(yStart)
            
            let (string, usedRect) = width(for: scheme)
            
            let label: ItemLabel
            let button: ItemButton
            
            if id < labels.count {
                label = labels[id]
                button = buttons[id]
            }
            else {
                label = ItemLabel(frame: .zero)
                self.labels.append(label)
                self.addSubview(label)
                
                button = ItemButton(schemeState: $schemes[id].state)
                self.buttons.append(button)
                self.addSubview(button)
            }
            
            label.update(usedRect.offsetBy(dx: convX.x, dy: convY.y), string)
            button.update(buttonRect.offsetBy(dx: convX.x, dy: convX.y))
            
            encountered += 1
        }
        
        if encountered < buttons.count {
            for i in stride(from: buttons.count - 1, through: encountered, by: -1) {
                buttons.remove(at: i).removeFromSuperview()
                labels.remove(at: i).removeFromSuperview()
            }
        }
    }
}
