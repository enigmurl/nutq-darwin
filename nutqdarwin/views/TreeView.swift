//
//  TreeView.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 7/3/23.
//

import SwiftUI


extension NSAttributedString.Key {
    static let schemeId = NSAttributedString.Key("SchemeIdIndex")
}

fileprivate let indentWidth: CGFloat = 5
fileprivate let hangingIndent: CGFloat = 5
fileprivate let eventWidth: CGFloat = 70
fileprivate let topPadding: CGFloat = 6

fileprivate let textAttributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.7),
    .font: NSFont.systemFont(ofSize: 12, weight: .regular)
]

fileprivate let mainAttributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: NSColor.black,
    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
]

fileprivate let mainWidth: CGFloat = {
    return NSString("0").size(withAttributes: mainAttributes).width
}()

fileprivate let mainHeight: CGFloat = {
    return NSString("0").size(withAttributes: mainAttributes).height
}()

#if os(macOS)

// rect relative to the line, last parameter is total width
func width(for scheme: SchemeItem) -> (NSAttributedString, NSRect, CGFloat) {
    var string = ""
    if scheme.start != nil {
        string += scheme.start!.dateString
        string += " \u{2192}"
    }
    if scheme.end != nil {
        if string.count == 0 {
            string += "\u{2192} " + scheme.end!.dateString
        }
        else {
            string += " " + (scheme.end!.dayDifference(with: scheme.start!) == 0 ? scheme.end!.timeString :  scheme.end!.dateString)
        }
    }
    
    switch scheme.repeats {
    case.none:
        break
    case .block:
        string += " block"
    }
    
    if string.count > 0 {
        string += " "
    }
    
    let nsString = NSAttributedString(string: string, attributes: textAttributes)
    let size = nsString.size()
    let containerWidth = ceil(size.width / mainWidth) * mainWidth
    let rect = NSRect(x: -containerWidth / 2 - size.width / 2, y: -size.height / 2 - mainHeight / 2, width: size.width, height: size.height)
    
    return (nsString, rect, containerWidth)
}

//basic text editor
// hard parts: getting text cell for the completion, but should still be doable
// diplaying finished starts is easy, editing is slightly harder

// plan: each line has an attribute for its id. Enumerate the ids and if we have a weird
/* partially inspired by code view */
// ok instead just set the line height of the next thing to be really high
final class TextView: NSTextView, NSTextStorageDelegate {
    var schemes: Binding<[SchemeItem]>!
    var memoizedIndexMap: [UUID: Int] = [:]
    var gutterView: GutterView!
    
    #warning("TODO not sure why our implementation of init isn't working; hard to even find where the NSTextView default constructor is?")
    static func factory(schemes: Binding<[SchemeItem]>) -> TextView {
        let ret = TextView()
        ret.schemes = schemes
        ret.gutterView = GutterView(schemes: schemes, layoutManager: ret.layoutManager!, textStorage: ret.textStorage!)
        ret.addSubview(ret.gutterView)

        ret.autoresizingMask = .width

        ret.backgroundColor = .clear
        ret.insertionPointColor = .black

        ret.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ret.textColor = mainAttributes[.foregroundColor] as? NSColor
        ret.selectedTextAttributes = [.backgroundColor: NSColor(red: 0.98, green: 0.89, blue: 0.67, alpha: 1)]

        ret.isAutomaticSpellingCorrectionEnabled = false
        ret.isAutomaticTextReplacementEnabled = false
        ret.isAutomaticTextCompletionEnabled = false
        ret.isAutomaticQuoteSubstitutionEnabled = false
        ret.isAutomaticDashSubstitutionEnabled = false
        ret.isAutomaticLinkDetectionEnabled = false
        ret.isAutomaticDataDetectionEnabled = false
        ret.textStorage?.delegate = ret
        ret.textContainerInset.height = topPadding
        
        return ret
    }
    
    func getIndex(_ id: UUID) -> Int {
        let ret = memoizedIndexMap[id] ?? 0
        if schemes[ret].id != id {
            let index = schemes.firstIndex(where: {$0.id == id}) ?? 0
            memoizedIndexMap[id] = index
            return index
        }

        return ret
    }

    override func insertNewline(_ sender: Any?) {
        self.insertNewline(prev: false)
    }
    
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        self.insertNewline(prev: true)
    }
    
    override func insertTab(_ sender: Any?) {
        self.insertTab()
    }
    
    override func insertBacktab(_ sender: Any?) {
        self.insertBacktab()
    }
    
    override func deleteBackward(_ sender: Any?) {
        self.deleteBackward()
    }
    
    override func deleteWordBackward(_ sender: Any?) {
        self.deleteBackwardsWord()
    }
    
    override func deleteToBeginningOfLine(_ sender: Any?) {
        self.deleteToBeginningOfLine()
    }
    
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        self.gutterView.needsLayout
    }
    
    func applyAttributes() {
//        textStorage?.enumerateAttribute(.schemeId, in: NSRange(location: 0, length: self.string.count)) { value, range, _ in
//            guard let id = value as? UUID else {
//                return
//            }
//
//            let index = getIndex(id)
//            let scheme = schemes.wrappedValue[index]
//            let (_, _, width) = width(for: scheme)
//
//            let paragraphStyle = NSMutableParagraphStyle()
//            paragraphStyle.headIndent = indentWidth * CGFloat(scheme.indentation)
//            paragraphStyle.firstLineHeadIndent = paragraphStyle.headIndent + width
//            paragraphStyle.headIndent += hangingIndent
//
//            textStorage?.removeAttribute(.strikethroughColor, range: range)
//            textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
//            textStorage?.addAttributes(mainAttributes, range: range)
//        }
    }
}

extension TextView {
    
    func deleteToBeginningOfLine() {
        
    }
    
    func deleteBackwardsWord() {
        
    }
    
    func deleteBackward() {
        
    }
    
    func insertBacktab() {
        
    }
    
    func insertTab() {
        
    }
    
    func insertNewline(prev: Bool) {
        
    }
}


class ItemButton: NSButton {
//    @Binding var scheme: SchemeItem
    
    func update(_ box: NSRect, toggled: Bool) {
        
    }
}

class ItemLabel: NSView {
    private var string: NSAttributedString = NSAttributedString(string: "")
    
    override func draw(_ dirtyRect: NSRect) {
//        let rect = self.convert(self.frame, from: self.superview)
        string.draw(in: dirtyRect)
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
    let layoutManager: NSLayoutManager
    let textStorage: NSTextStorage
    
    var buttons: [UUID: ItemButton] = [:]
    var labels: [UUID: ItemLabel] = [:]
    
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
    
    func getIndex(_ id: UUID) -> Int {
        return (self.superview as! TextView).getIndex(id)
    }
    
    func convert(_ rect: NSRect) -> NSRect {
        var ret = self.convert(rect, from: self.superview!)
        ret.origin.y -= topPadding
        return ret
    }
    
    func convert(_ point: NSPoint) -> NSPoint {
        var ret = self.convert(point, from: self.superview!)
        ret.y -= topPadding
        return ret
    }
    
    override func layout() {
        self.needsDisplay = true
        // delete olds
        var encountered: Set<UUID> = Set()
        
        // we dont use the given range because that wouldn't cover the entire scheme
        textStorage.enumerateAttribute(.schemeId, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let id = value as? UUID /* ,edited.intersection(range)?.length ?? 0 > 0 */ else {
                return
            }
            
            encountered.insert(id)
            
            let label: ItemLabel
            let button: ItemButton
           
            
            let scheme = schemes[getIndex(id)]

            let glyphRange = self.layoutManager.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: self.layoutManager.textContainers[0])
            let yStart = rect.origin
            let convertedStart = self.convert(yStart)

            let (string, usedRect, _) = width(for: scheme)
            
            
            if let lb = self.labels[id] {
                label = lb
            }
            else {
                label = ItemLabel(frame: usedRect.offsetBy(dx: convertedStart.x, dy: convertedStart.y))
                self.labels[id] = label
                self.addSubview(label)
            }

            if let bn = self.buttons[id] {
                button = bn
            }
            else {
                button = ItemButton()
                self.buttons[id] = button
                self.addSubview(button)
            }
           
            label.update(usedRect.offsetBy(dx: convertedStart.x, dy: convertedStart.y), string)
            button.update(.zero, toggled: false)
        }
     
        if encountered.count < buttons.count {
            /* remove olds */
            for button in buttons {
                if !encountered.contains(button.key) {
                    button.value.removeFromSuperview()
                }
            }
            
            for item in labels {
                if !encountered.contains(item.key) {
                    item.value.removeFromSuperview()
                }
            }
            
            buttons = buttons.filter { encountered.contains($0.key) }
            labels = labels.filter { encountered.contains($0.key) }
        }
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in subviews {
            if let ret = subview.hitTest(point) {
                return ret
            }
        }
        
        return nil
    }
}

struct TreeView: NSViewRepresentable {
    @Binding var scheme: SchemeState

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalRuler  = false
        scroll.backgroundColor = NSColor(red: 0.841, green: 0.888, blue: 0.888, alpha: 1)
        
        let ret = TextView.factory(schemes: $scheme.schemes) //TextView(schemes: $scheme.schemes)
        
        self.attribute(ret)
        
        scroll.documentView = ret
        return scroll
    }
    
    func attribute(_ document: TextView) {
        let string = NSMutableAttributedString()
        for scheme in scheme.schemes {
            let currString = scheme == self.scheme.schemes.last ? scheme.text : scheme.text + "\n"
            string.append(NSAttributedString(string: currString, attributes: [.schemeId: scheme.id]))
        }
        
        document.textStorage?.setAttributedString(string)
        document.applyAttributes() // refresh paragraph style
    }
    
    func updateNSView(_ nsView: NSScrollView, context: NSViewRepresentableContext<Self>) {
        let starts = scheme.schemes.map { $0.start }
        let ends   = scheme.schemes.map { $0.end }
        let repeats = scheme.schemes.map { $0.repeats }

        /* the only external modification we care about are timing changes, indents, text are handled within */
        if context.coordinator.previousStarts != starts || context.coordinator.previousEnds != ends || context.coordinator.previousEnds != ends {
            self.attribute(nsView.documentView as! TextView)
        }

        context.coordinator.previousStarts = starts
        context.coordinator.previousEnds   = ends
        context.coordinator.previousRepeats = repeats
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previousStarts: [Date?] = []
        var previousEnds: [Date?] = []
        var previousRepeats: [SchemeRepeat] = []
    }
}

struct TreeView_Previews: PreviewProvider {
    static var previews: some View {
        TreeView(scheme: .constant(debugSchemes[0]))
    }
}
#endif
