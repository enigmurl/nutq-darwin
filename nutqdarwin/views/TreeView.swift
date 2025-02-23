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

fileprivate let bottomPadding: CGFloat = 200

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

fileprivate let defaultStartOffset: TimeInterval = 9 * .hour
fileprivate let defaultEndOffset: TimeInterval = 23 * .hour

fileprivate func standardAvailable(_ start : Date?, _ end: Date?) -> Date {
    Date.now.startOfDay()
}

fileprivate func standardStart(_ end: Date?) -> Date {
    if let end = end {
        return end.startOfDay() + defaultStartOffset
    }
    else {
        let raw = Date.now + 15 * TimeInterval.minute
        return Calendar.current.date(bySetting: .second, value: 0, of: raw) ?? raw
    }
}

fileprivate func standardEnd(_ start: Date?) -> Date {
    (start ?? .now).startOfDay() + defaultEndOffset
}

#if os(macOS)
fileprivate let buttonRect = CGRect(x: -16, y: mainHeight / 2 - 6.5, width: 15, height: 15)
#else
fileprivate let buttonRect = CGRect(x: -15, y: -mainHeight / 2 - 6.5, width: 14, height: 14)
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
    
    if let available = scheme.available {
        string += " available \(available.dayString(todayString: "today"))"
    }

    switch scheme.repeats {
    case .None:
        break
    case .Block:
        string += " block"
    }
    
    if let first = scheme.state.firstIndex(where: { $0.progress != -1 }), scheme.state[first].delay != 0 {
        let (start_delay, _) = singularSchemeNotificationDelay(scheme: scheme, index: first)
        if let time = (scheme.start ?? scheme.end)?.addingTimeInterval(start_delay) {
            string += "       notify \(time.dateString)"
        }
    }
    
    
    
    if scheme.start != nil && scheme.end != nil && scheme.start! >= scheme.end! {
        string += "       WARNING: start is after end"
    }
    
    if scheme.available != nil && (scheme.start ?? scheme.end) != nil && (scheme.start ?? scheme.end)! < scheme.available! {
        string += "       WARNING: available is after event"
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

enum Popover {
    case start
    case end
    case available
    case block
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
    var applyingInitialAttributes = false
    var pipe: AnyCancellable!
    var deleteRange: Range<Int>?
    
    var _undoManager = UndoManager()
    override var undoManager: UndoManager? {
       _undoManager
    }
    
    var popoverSubview: NSView? = nil
    var popoverIndex: Int? = nil
    var popover: Popover? {
        didSet {
            if popover == nil && oldValue != nil, let index = popoverIndex {
                window?.makeFirstResponder(self)
                let line = self.lines(startIndex: 0)[index].0
                self.setSelectedRange(NSRange(location: line.upperBound - 1, length: 0))
            }
            
            self.popoverSubview?.removeFromSuperview()
            self.popoverSubview = nil
            self.breakUndoCoalescing()
        }
    }
    
    var sr: NSRange {
        get { self.selectedRange() }
        set { self.setSelectedRange(newValue)}
    }
    
    var ts: NSTextStorage { self.textStorage! }
    
    var text: String {
        get { self.string }
        set { self.string = newValue}
    }

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
    
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.characters?.contains("z") ?? false {
                if event.modifierFlags.contains(.shift) {
                    if _undoManager.canRedo {
                        _undoManager.redo()
                    }
                } else {
                    if _undoManager.canUndo {
                        _undoManager.undo()
                    }
                }
                
                return
            }
        }
        
        // Handle other key events as needed
        super.keyDown(with: event)
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
        if !self.applyingInitialAttributes {
            self.fixSchemes(range: editedRange)
        }
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
            if self.sr.location == self.ts.length && self.sr.location >= 1 {
                self.sr.location -= 1
            }
            self.scrollRangeToVisible(self.selectedRange())
            initialFocused = true
        }
        
        if self.popover != nil {
            self.popoverIndex = nil // elide shift of selection
            self.popover = nil
        }
        
        return true
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
        self.handles = []
        self.pipe.cancel()
        initialFocused = false
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let popover = self.popoverSubview, popover.frame.contains(point) {
            return popover
        }
        
        return self
    }
}

class ItemButton: NSButton {
    @Binding var schemeState: [SchemeSingularState]
    var imageName: String?
    
    init(schemeState: Binding<[SchemeSingularState]>) {
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
        
        let imageName = schemeState.allSatisfy { $0.progress == -1 } ? "checkmark.square" : (schemeState.count > 1 ? "dot.square" : "square")
        
        if imageName != self.imageName {
            self.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)?
                .tint(color: NSColor(red: CGFloat(11 / 255.0), green: CGFloat(79 / 255.0), blue: CGFloat(121 / 255.0), alpha: 1))
            self.imageName = imageName
        }
    }
   
    // not sure why this needs to be done in the first place?
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self.bounds.contains(point) ? self : nil
    }
    
    func toggle() {
        if schemeState.count == 1 {
            schemeState[0].progress = -1 - schemeState[0].progress
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
        var point = point
        point.y = self.bounds.height - point.y
        
        return documentView?.hitTest(self.convert(point, to: documentView))
    }
}

struct TreeNativeView: NSViewRepresentable {
    // we want to be notified of changes to specific schemes, but not insertions or deletions
    @ObservedObject var scheme: SchemeItemList
    let menu: MenuState
    let enabled: Bool

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSScrollView {
        let scroll = TouchThroughScrollView()
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalRuler  = false
        scroll.backgroundColor = backgroundColor
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomPadding, right: 0)
        scroll.automaticallyAdjustsContentInsets = false
        
        let ret = TreeTextView.factory(schemes: $scheme.schemes)
        ret.listen(to: menu)
        ret.isEditable = enabled
        
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
    var applyingInitialAttributes = false
    var pipe: AnyCancellable!
    var deleteRange: Range<Int>?
    
    var sr: NSRange {
        get { self.selectedRange }
        set { selectedRange = newValue }
    }
    
    var ts: NSTextStorage { self.textStorage }
    
    var popoverSubview: UIView? = nil
    var popoverIndex: Int? = nil
    var popover: Popover? {
        didSet {
            if popover == nil && oldValue != nil, let index = popoverIndex {
                let _ = self.becomeFirstResponder()
                let line = self.lines(startIndex: 0)[index].0
                self.sr = NSRange(location: line.upperBound - 1, length: 0)
            }
            
            self.popoverSubview?.removeFromSuperview()
            self.popoverSubview = nil
        }
    }

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
    
    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
        
        if self.popover != nil {
            self.popoverIndex = nil // elide shift of selection
            self.popover = nil
        }
        
        return true
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
    @Binding var schemeState: [SchemeSingularState]
    var imageName: String?
    
    init(schemeState: Binding<[SchemeSingularState]>) {
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
        
        let imageName = schemeState.allSatisfy { $0.progress == -1 } ? "checkmark.square" : (schemeState.count > 1 ? "dot.square" : "square")
        
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
            schemeState[0].progress = -1 - schemeState[0].progress
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
    let enabled: Bool

    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIScrollView {
        let ret = TreeTextView.factory(schemes: $scheme.schemes)
        ret.backgroundColor = backgroundColor
        ret.listen(to: menu)
        ret.textContainerInset = .init(top: 0, left: 0, bottom: 200, right: 0)
        ret.isEditable = enabled
        
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
    let enabled: Bool
    
    @FocusState var focused
    
    var mainView: some View {
        TreeNativeView(scheme: scheme, menu: menu, enabled: enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .focused($focused)
            .onAppear {
                focused = true
            }
            .onChange(of: scheme.id) {
                focused = true
            }
    }
    
#if os(iOS)
    var controls: some View {
        HStack {
            Button {
                menu.send(.deindent)
            } label: {
                Image(systemName: "decrease.indent")
            }
            
            Button {
                menu.send(.indent)
            } label: {
                Image(systemName: "increase.indent")
            }
            
            Spacer()
            
            Button("Start") {
                menu.send(.toggleStartView)
            }
            
            Button("End") {
                menu.send(.toggleEndView)
            }
            
            Button("Block") {
                menu.send(.toggleBlockView)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
    
    var body: some View {
        VStack {
            mainView
            self.controls
        }
        .background(Color(red: 0.841, green: 0.888, blue: 0.888))
    }
    
#else
    var body: some View {
        self.mainView
            .background(Color(red: 0.841, green: 0.888, blue: 0.888))
    }
#endif
  
    
}

extension TreeTextView {
   
    func subscriber(for scheme: SchemeItem) -> AnyCancellable {
        var count = 0
        let ret = scheme.mergedStatePublisher.receive(on: RunLoop.main).sink { _ in
            count += 1
            #warning("TODO not a great solution")
            if count > 4 {
                let (ranges, _) = self.lines(startIndex: 0)[self.schemes.wrappedValue.firstIndex(of: scheme)!]
                self.applyDerivedStyles(range: ranges)
            }
        }
        
        return ret
    }
    
    func setBinding<T>(_ binding: Binding<T>, old: T, new: T) where T: Equatable {
        if old == new {
            return
        }
        
        binding.wrappedValue = new
        
        undoManager?.registerUndo(withTarget: self) {
            $0.setBinding(binding, old: new, new: old)
        }
    }
    
    func handle(action: MenuAction, publisher: MenuState) {
#if os(macOS)
        if self.window?.firstResponder != self && self.popoverSubview == nil {
            return
        }
        let timeWidth: CGFloat = 240
        let blockWidth: CGFloat = 450
#else
        if !self.isFirstResponder && self.popoverSubview == nil {
            return
        }
        let timeWidth: CGFloat = 250
        let blockWidth: CGFloat = 330
#endif
        
        guard sr.location != self.ts.length, let schemeIndex = self.ts.attribute(.index, at: self.sr.location, effectiveRange: nil) as? Int else {
            return
        }
        
        let scheme = self.schemes.wrappedValue[schemeIndex]
        let projected = ObservedObject(wrappedValue: self.schemes.wrappedValue[schemeIndex]).projectedValue
        
        switch action {
        case .indent:
            self.tab(delta: 1)
            
        case .deindent:
            self.tab(delta: -1)
            
        case .toggle:
            self.ts.enumerateAttribute(.index, in: self.lineRange()) { value, range, _ in
                guard let index = value as? Int else {
                    return
                }
                
                if self.schemes.wrappedValue[index].state.count == 1 {
                    self.schemes.wrappedValue[index].state[0].progress = -1 - self.schemes.wrappedValue[index].state[0].progress
                }
            }
            
        case .toggleStartView:
            let initial = scheme.start
            scheme.start = scheme.start ?? standardStart(scheme.end)
            
            self.popover = self.popover == .start ? nil : .start
            
            if self.popover == .start {
                self.popoverIndex = schemeIndex
                
                let binding = projected.start
                let view = Time(label: "Start", date: binding, state: projected.state, menuState: publisher, callback: self, initial: initial) {
                    self.popover = nil
                }
                
                self.addPopover(view: view, for: schemeIndex, width: timeWidth, height: 200)
            }
        case .toggleAvailableView:
            let initial = scheme.available
            scheme.available = scheme.available ?? standardAvailable(scheme.start, scheme.end)
            
            self.popover = self.popover == .start ? nil : .start
            
            if self.popover == .start {
                self.popoverIndex = schemeIndex
                
                let binding = projected.available
                let view = Time(label: "Available", date: binding, state: projected.state, menuState: publisher, callback: self, initial: initial) {
                    self.popover = nil
                }
                
                self.addPopover(view: view, for: schemeIndex, width: timeWidth, height: 200)
            }
        
        case .toggleEndView:
            let initial = scheme.end
            scheme.end = scheme.end ?? standardEnd(scheme.start)
            
            self.popover = self.popover == .end ? nil : .end
            
            if self.popover == .end {
                self.popoverIndex = schemeIndex
                
                let binding = projected.end
                let view = Time(label: "End", date: binding, state: projected.state, menuState: publisher, callback: self, initial: initial) {
                    self.popover = nil
                }
                
                self.addPopover(view: view, for: schemeIndex, width: timeWidth, height: 200)
            }
            
        case .toggleBlockView:
            let initial = scheme.repeats
            if case .Block = scheme.repeats { }
            else {
                scheme.repeats = .Block(block: .init())
            }
            
            self.popover = self.popover == .block ? nil : .block
            
            if self.popover == .block {
                self.popoverIndex = schemeIndex
                
                let view = Block(scheme: scheme, menuState: publisher, callback: self, initial: initial) {
                    self.popover = nil
                }
                
                self.addPopover(view: view, for: schemeIndex, width: blockWidth, height: 40)
            }
            
        case .disableStart:
            self.setBinding(projected.start, old: scheme.start, new: nil)
            scheme.start = nil
            if self.popover == .start {
                self.popover = nil
            }
        case .disableAvailable:
            self.setBinding(projected.available, old: scheme.available, new: nil)
            scheme.available = nil
            if self.popover == .start {
                self.popover = nil
            }

        case .disableEnd:
            self.setBinding(projected.end, old: scheme.end, new: nil)
            if self.popover == .end {
                self.popover = nil
            }
            
        case .disableBlock:
            self.setBinding(projected.repeats, old: scheme.repeats, new: .None)
            scheme.state = [scheme.state.first ?? SchemeSingularState()]
            
            if self.popover == .block {
                self.popover = nil
            }
            
        default:
            break
        }
        
        self.applyDerivedStyles(range: self.lineRange())
        self.gutterView.setNeedsLayout()
    }
    
    func listen(to publisher: MenuState) {
        self.pipe = publisher.sink { action in
            self.handle(action: action, publisher: publisher)
        }
    }
    
    func addPopover(view: some View, for index: Int, width: CGFloat, height: CGFloat) {
        let lm = self.gutterView.layoutManager
        let tc = lm.textContainers[0]
        let range = self.lines(startIndex: 0)[index].0
        
        let xRange = lm.glyphRange(forCharacterRange: NSRange(location: range.lowerBound, length: 0), actualCharacterRange: nil)
        let yRange = lm.glyphRange(forCharacterRange: NSRange(location: range.upperBound - 1, length: 0), actualCharacterRange: nil)
        
        let xRect = lm.boundingRect(forGlyphRange: xRange, in: tc)
        let yRect = lm.boundingRect(forGlyphRange: yRange, in: tc)
        
        var yStart = yRect.origin
        yStart.y += yRect.height + timeHeight
        
        var xStart = xRect.origin
        xStart.y += xRect.height
        
#if os(macOS)
        let base = NSHostingController(rootView: view)
#else
        let base = UIHostingController(rootView: view)
#endif
        base.view.frame = .init(x: xStart.x, y: yStart.y, width: width, height: height)
        
        self.popoverSubview = base.view
        self.addSubview(base.view)
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
        
        // not perfect in the case that delta < 0
        undoManager?.registerUndo(withTarget: self) {
            $0.tab(delta: -delta)
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
        
        if scheme.start != nil || scheme.end != nil || scheme.repeats != .None {
            style.paragraphSpacing = timeHeight
        }
        
        ts.addAttribute(.paragraphStyle, value: style, range: range)
        #if os(iOS)
        ts.addAttribute(.font, value: UIFont.systemFont(ofSize: 14), range: range)
        #else
        ts.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: range)
        #endif
        
        if scheme.complete {
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
        let old = self.sr
        self.ts.append(NSAttributedString(string: "\n"))
        self.sr = old
        self.addNewLineFlag = false
        
        self.undoManager?.registerUndo(withTarget: self) {
            $0.removeAuxiliaryLine()
        }
    }
    
    func removeAuxiliaryLine() {
        let old = self.sr
        self.text.removeLast()
        self.sr = old
        
        self.undoManager?.registerUndo(withTarget: self) {
            $0.addAuxiliaryLine()
        }
    }
    
    func delete(range: Range<Int>) {
        let items = Array(schemes.wrappedValue[range])
        self.schemes.wrappedValue.removeSubrange(range)
        self.handles.removeSubrange(range)
        
        self.undoManager?.registerUndo(withTarget: self) {
            $0.insert(items: items, at: range.lowerBound)
            $0.gutterView.setNeedsLayout()
        }
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
    }
    
    func applyInitialAttributes() {
        self.applyingInitialAttributes = true
        for (subRange, _) in self.lines(startIndex: 0) {
            applyDerivedStyles(range: subRange)
        }
        self.applyingInitialAttributes = false
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
