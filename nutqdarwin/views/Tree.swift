//
//  Tree.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/13/23.
//

import SwiftUI


//not the greatest conventions overall, fix!

fileprivate let defaultStartOffset: TimeInterval = 9 * .hour
fileprivate let defaultEndOffset: TimeInterval = 23 * .hour

fileprivate func blankEditor(_ str: String, indentation: Int = 0) -> SchemeItem {
    return SchemeItem(state: [0], text: str, repeats: .none, indentation: indentation)
}

fileprivate struct BackgroundView: View {
    let showStroke: Bool
    let radius: CGFloat
   
    init(showStroke: Bool = true, radius: CGFloat = 3) {
        self.showStroke = showStroke
        self.radius = radius
    }
    
    var body: some View {
        ZStack {
            BlurView()
                .opacity(0.7)
            
            Color.gray
                .opacity(0.1)
           
            if showStroke {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.gray, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(radius: self.radius)
    }
}

fileprivate extension View {
    func blueBackground(padding: CGFloat = 3) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1)
            }
    }
}

#if os(macOS)
// got to be a better way..., but it seems like it's pretty hard to interop
// with focus state
fileprivate var inAppearingContext = false
fileprivate class FocusableTextField: NSTextField {
    var focus: FocusState<TreeFocusToken?>.Binding!
    var targetFocus: TreeFocusToken!
    
    override func becomeFirstResponder() -> Bool {
        let status = super.becomeFirstResponder()
        if status {
            focus.wrappedValue = targetFocus
        }
        return status
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        if focus.wrappedValue == targetFocus {
            if !inAppearingContext {
                focus.wrappedValue = nil
            }
        }
    }
}

fileprivate struct EnterableTextField: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var focus: TreeFocusToken?
    let prevFocus: TreeFocusToken
    let targetFocus: TreeFocusToken
    let nextFocus: TreeFocusToken
    
    func makeNSView(context: Context) -> FocusableTextField  {
        let field = FocusableTextField()
        field.stringValue = text
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.isEditable = true
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        
        field.delegate = context.coordinator
        
        field.focus = $focus
        field.targetFocus = targetFocus
        
        return field
    }
    
    func updateNSView(_ nsView: FocusableTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
//        if focus == targetFocus && nsView.currentEditor() == nil {
//            nsView.window?.makeFirstResponder(nsView)
//        }
//        else if focus != targetFocus && nsView.currentEditor() == nil {
//            nsView.window?.firstResponder?.resignFirstResponder()
//        }
    }
    
    func makeCoordinator() -> Delegate {
        Delegate(text: $text, focusState: $focus, prevFocus: prevFocus, targetFocus: targetFocus, nextFocus: nextFocus)
    }
    
    class Delegate: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        @FocusState.Binding var focusState: TreeFocusToken?
        
        let prevFocus: TreeFocusToken
        let targetFocus: TreeFocusToken
        let nextFocus: TreeFocusToken
        
        init(text: Binding<String>, focusState: FocusState<TreeFocusToken?>.Binding, prevFocus: TreeFocusToken, targetFocus: TreeFocusToken, nextFocus: TreeFocusToken) {
            _text = text
            _focusState = focusState
            self.prevFocus = prevFocus
            self.targetFocus = targetFocus
            self.nextFocus = nextFocus
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                return true
            }
            else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                focusState = nextFocus
                return true
            }
            else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                focusState = prevFocus
                return true
            }
            
            return false
        }
    
        func controlTextDidChange(_ obj: Notification) {
            guard let textfield = obj.object as? NSTextField else {
                return
            }
            
            if text != textfield.stringValue {
                text = textfield.stringValue
            }
        }
    }
}

fileprivate struct ItemTextField: View {
    @Binding var text: String
    @FocusState.Binding var focus: TreeFocusToken?
    let prevFocus: TreeFocusToken
    let targetFocus: TreeFocusToken
    let nextFocus: TreeFocusToken
    
    var body: some View {
        EnterableTextField(text: $text, focus: $focus, prevFocus: prevFocus, targetFocus: targetFocus, nextFocus: nextFocus)
            .padding(.leading, -2) // not sure whats the cause of this
            .focused($focus, equals: targetFocus)
    }
}

#else
fileprivate struct ItemTextField: View {
    @Binding var text: String
    @FocusState.Binding var focus: TreeFocusToken?
    let targetFocus: TreeFocusToken

    var body: some View {
        TextField("", text: $text)
            .focused($focus, equals: targetFocus)
    }
}
#endif

//use march since it has 31 days, some date in the past
fileprivate let referenceDate = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    dateFormatter.timeZone = TimeZone.current
    dateFormatter.locale = Locale.current
    return dateFormatter.date(from: "2000-03-14T12:00:00")!
}()

fileprivate let digitMap: [Calendar.Component: Int] = [.minute: 2, .hour: 2, .day: 2, .month: 2, .year: 4]
fileprivate let minMap: [Calendar.Component: Int] = [.minute: 0, .hour: 0, .day: 1, .month: 1, .year: 1]
fileprivate let maxMap: [Calendar.Component: Int] = [.minute: 59, .hour: 23, .day: 31, .month: 12, .year: 9999]

struct ItemEditor: View {
    @FocusState.Binding var focus: TreeFocusToken?
    let prevFocus: TreeFocusToken
    let nextFocus: TreeFocusToken
    
    @Binding var schemeNode: SchemeItem
    @Binding var allNodes: [SchemeItem]
    
    @EnvironmentObject var envState: EnvState
    
    @EnvironmentObject var menuDispatcher: MenuState
    @State var showingStart = false
    @State var showingEnd   = false
    @State var showingBlock = false
    
    @State var timeComponent: Calendar.Component? = nil
    @State var timeBuffer: String? = nil
    @State var timeSettled = 0 // swiftui bug of selection not being proper
   
    func reallySet(_ comp: Calendar.Component, value: Int, date: Date) -> Date {
        var components = NSCalendar.current.dateComponents([.minute, .hour, .day, .month, .year], from: date)
        components.setValue(value, for: comp)
        return NSCalendar.current.date(from: components)!
    }
    
    func field(date: Binding<Date?>, focus: Int, comp: Calendar.Component) -> some View {
        func write(comp: Calendar.Component?) {
            guard let comp = comp, let timeBuffer = timeBuffer, let dateVal = date.wrappedValue else {
                return
            }
            
            let mn = minMap[comp]!
            let mx = maxMap[comp]!
            
            let oldComponent = NSCalendar.current.component(comp, from: dateVal)
            let clipped = timeBuffer.filter {$0.isNumber}
            let newComponent = min(mx, max(mn, Int(clipped) ?? mn))
            
            // has 31 days in march
            let reference = reallySet(comp, value: oldComponent, date: referenceDate)
            let newReference = reallySet(comp, value: newComponent, date: referenceDate)
            
            var newVal: Date = dateVal + newReference.timeIntervalSince(reference)
            
            // kind of hacky, but relaisitcally when you change month you want date to reset sooo
            if comp == .month && newComponent != oldComponent {
                newVal = reallySet(.day, value: 1, date: newVal)
                newVal = reallySet(.month, value: newComponent, date: newVal)
            }
            else if comp == .year && newComponent != oldComponent {
                newVal = reallySet(.day, value: 1, date: newVal)
                newVal = reallySet(.month, value: 1, date: newVal)
                newVal = reallySet(.year, value: newComponent, date: newVal)
            }
            
            if newVal != dateVal {
                envState.writeBinding(binding: date, newValue: newVal)
            }
        }
        
        let digits = digitMap[comp]!
        let raw = String(format: "%0\(digits)d", NSCalendar.current.component(comp, from: (date.wrappedValue ?? Date.now)!))
        
        return TextField("", text: Binding(
            get: {
                if self.focus?.uuid == self.schemeNode.id && timeSettled == self.focus?.subtoken && timeSettled == focus && timeBuffer != nil {
                    return timeBuffer!
                }
                else {
                    return raw
                }
            }, set: { newValue in
                if self.focus?.uuid == self.schemeNode.id && self.focus?.subtoken == focus {
                    timeBuffer = String(
                        newValue
                        .filter { $0.isNumber }
                        .suffix(digits)
                    )
                }
            }))
                .multilineTextAlignment(.trailing)
                .focused(self.$focus, equals: TreeFocusToken(uuid: self.schemeNode.id, subtoken: focus))
                .frame(maxWidth: CGFloat(digits) * 7.5)
                .onAppear {
                    timeComponent = nil
                }
                .onChange(of: self.focus) { mf in
                    if mf?.uuid == schemeNode.id && mf?.subtoken == focus {
                        write(comp: timeComponent)
                        // NOTE: cannot be cached with other string
                        // since may have changed as result of write
                        let current = String(format: "%0\(digits)d", NSCalendar.current.component(comp, from: date.wrappedValue!))
                        timeBuffer = current
                        timeComponent = comp
                        timeSettled = focus
                    }
                }
                .onDisappear {
                    if let comp = timeComponent {
                        write(comp: comp)
                    }
                    timeComponent = nil
                    timeBuffer = nil
                }
                .onSubmit {
                    write(comp: comp)
                    
                    self.focus?.subtoken = focus + 1
                }
    }
    
    func dateEditor(_ label: String, date: Binding<Date?>) -> some View {
        HStack {
            Text(label)
                .font(.body.bold())
            
            HStack(spacing: 0) {
                //YYYY
                self.field(date: date, focus: 1, comp: .year)
                Text("/")
                    .padding(.leading, 2)
               
                //MM
                self.field(date: date, focus: 2, comp: .month)
                Text("/")
                    .padding(.leading, 2)
               
                //DD
                self.field(date: date, focus: 3, comp: .day)
            }
            .monospaced()
            .blueBackground()
            
            Text("at")
            
            HStack(spacing: 0) {
                //HH
                self.field(date: date, focus: 4, comp: .hour)
                Text(":")
                
                //MM
                self.field(date: date, focus: 5, comp: .minute)
            }
            .monospaced()
            .blueBackground()
        }
        .textFieldStyle(.plain)
        .onSubmit {
            self.focus?.subtoken = 0
            self.resetModifiers()
        }
        .onAppear {
            self.focus?.subtoken = 3
            inAppearingContext = true
        }
    }
   
    @State private var blockBuffer = ""
    
    func blockEditor(_ label: String, schemeRepeat: Binding<SchemeRepeat> ) -> some View {
        let blockBinding = Binding(get: {
            guard case let SchemeRepeat.block(block) = schemeRepeat.wrappedValue else {
                return SchemeRepeat.Block()
            }
            
            return block
        }, set: { val in
            schemeRepeat.wrappedValue = .block(block: val)
            
            /* ensure state is proper */
            let target = val.remainders.count * val.blocks
            if self.schemeNode.state.count > target {
                self.schemeNode.state.removeLast(self.schemeNode.state.count - target)
            }
            else if self.schemeNode.state.count < target {
                self.schemeNode.state.append(contentsOf: [Int](repeating: 0, count: target - self.schemeNode.state.count))
            }
            /* autocompletion of events may be slightly lagged, but generally it's fine */
        })
        
        return (
            HStack(spacing: 4) {
                Text(label)
                    .font(.body.bold())
                    .padding(.trailing, 4)
                
                Text("remainders")
                TextField("", text: Binding(get: {
                    blockBuffer
                }, set: { str in
                    blockBuffer = str.filter {$0.isNumber || $0 == ","}
                    blockBinding.wrappedValue.remainders = blockBuffer
                        .split(separator: ",")
                        .map { Int($0) ?? 0 }
                }))
                    .focused($focus, equals: TreeFocusToken(uuid: schemeNode.id, subtoken: 1))
                    .frame(maxWidth: 60)
                    .blueBackground()
                    .padding(.trailing, 4)
                
                Text("blocks")
                TextField("", text: Binding(digits: blockBinding.blocks, min: 1, max: SchemeRepeat.Block.maxBlocks))
                    .focused($focus, equals: TreeFocusToken(uuid: schemeNode.id, subtoken: 2))
                    .frame(maxWidth: 20)
                    .blueBackground()
                    .padding(.trailing, 4)
                
                Text("modulus")
                TextField("", text: Binding(digits: blockBinding.modulus, min: 1))
                    .focused($focus, equals: TreeFocusToken(uuid: schemeNode.id, subtoken: 3))
                    .frame(maxWidth: 20)
                    .blueBackground()
                    .padding(.trailing, 2)

                Text("(days)")
                    .font(.caption2.lowercaseSmallCaps())
            }
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .onAppear {
                self.focus?.subtoken = 1
                blockBuffer = blockBinding.wrappedValue.remainders
                    .map { String($0)}
                    .joined(separator: ",")
            }
            .onDisappear {
                // not necessary (or guaranteed to be called), but generally useful
                blockBinding.wrappedValue.remainders = Array(Set(
                    blockBuffer
                        .split(separator: ",")
                        .map { min(blockBinding.wrappedValue.modulus - 1, max(Int($0) ?? 0, 0)) }
                )).sorted()
            }
            .onSubmit {
                self.focus?.subtoken = 0
                self.resetModifiers()
            }
        )
    }
    
    var modifiers: some View {
        HStack {
            VStack {
                if showingStart {
                    self.dateEditor("Starts", date: $schemeNode.start)
                }
                
                if showingEnd {
                    self.dateEditor("Ends", date: $schemeNode.end)
                }
                
                if showingBlock {
                    self.blockEditor("Block Repeat", schemeRepeat: $schemeNode.repeats)
                }
            }
            .padding(6)
            .background {
                BackgroundView()
            }
            .padding(.vertical, 1)
            
            Spacer()
        }
    }
    
    var captions: some View {
        HStack(spacing: 2) {
            if self.schemeNode.start != nil || self.schemeNode.end != nil || self.schemeNode.repeats != .none {
                Group {
                    if let start = self.schemeNode.start {
                        Text(start.dateString)
                    }
                    
                    if self.schemeNode.start != nil || self.schemeNode.end != nil {
                        Image(systemName: "arrow.right")
                    }
                    
                    if let end = self.schemeNode.end {
                        if self.schemeNode.start != nil && end.dayDifference(with: self.schemeNode.start!) == 0 {
                            Text(end.timeString)
                        }
                        else {
                            Text(end.dateString)
                        }
                    }
                    
                    switch self.schemeNode.repeats {
                    case .none:
                        EmptyView()
                    case .block(_):
                        Text("block")
                            .foregroundColor(.blue)
                    }
                }
                .font(.caption2)
                .padding(.bottom, 2)
            }
            else {
                Color.clear
                    .frame(maxHeight: 0)
                    .padding(.bottom, 7)
            }
        }
    }
   
    var anyModifiers: Bool {
        showingStart || showingEnd || showingBlock
    }
    
    func resetModifiers() {
        showingStart = false
        showingEnd = false
        showingBlock = false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 5) {
                if schemeNode.state.allSatisfy({ $0 == -1 }) {
                    Button {
                        if schemeNode.state.count == 1 {
                            schemeNode.state[0] = 0
                        }
                    } label: {
                        Image(systemName: "checkmark.square")
                            .resizable()
                            .opacity(0.7)
                            .frame(width: 15, height: 15)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(schemeNode.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        self.captions
                    }
                    .opacity(0.7)
                    .strikethrough(color: .red)
                }
                else {
                    Button {
                        if schemeNode.state.count == 1 {
                            schemeNode.state[0] = -1
                        }
                    } label: {
                        Image(systemName: schemeNode.state.count > 1 ? "dot.square" : "square")
                            .resizable()
                            .frame(width: 15, height: 15)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)

                    // disabled doesn't look nice
                    
                    VStack(alignment: .leading, spacing: 0) {
                        ItemTextField(text: $schemeNode.text, focus: $focus, prevFocus: prevFocus, targetFocus: TreeFocusToken(uuid: schemeNode.id, subtoken: 0), nextFocus: nextFocus)
                            .textFieldStyle(.plain)
                        
                        self.captions
                    }
                }
            }

            if self.anyModifiers && focus?.uuid == self.schemeNode.id {
                // focus anchor
                EmptyView()
                    .focused($focus, equals: TreeFocusToken(uuid: schemeNode.id, subtoken: -1))
                
                Color.clear
                    .frame(maxHeight: 0)
                    .overlay(alignment: .top) {
                        self.modifiers
                    }
            }
        }
        //hm surely there's a less symmetric way...
        .onReceive(menuDispatcher, perform: self.handleMenuAction(_:))
        #if os(macOS)
        .onExitCommand {
            resetModifiers()
        }
        #endif
        .onChange(of: focus) { [focus] newFocus in
            if newFocus?.uuid != self.schemeNode.id {
                resetModifiers()
            }
            else if focus?.uuid != newFocus?.uuid {
                resetModifiers()
            }
            inAppearingContext = false
        }
    }
    
    func handleMenuAction(_ action: MenuAction) {
        guard focus?.uuid == schemeNode.id else {
            return
        }
        
        switch (action) {
        case .toggleStartView:
            if !showingStart {
                if schemeNode.start == nil {
                    schemeNode.start = .now.startOfDay() + defaultStartOffset
                }
               
                self.resetModifiers()
                self.showingStart = true
            }
            else {
                
                focus?.subtoken = 0
                self.resetModifiers()
                self.showingStart = false
            }
        case .disableStart:
            schemeNode.start = nil
            self.showingStart = false
            focus?.subtoken = 0
        case .toggleEndView:
            if !showingEnd {
                if schemeNode.end == nil {
                    schemeNode.end = .now.startOfDay() + defaultEndOffset
                }
                
                self.resetModifiers()
                self.showingEnd = true
            }
            else {
                
                focus?.subtoken = 0
                self.resetModifiers()
                self.showingEnd = false
            }
        case .disableEnd:
            schemeNode.end = nil
            self.showingEnd = false
            focus?.subtoken = 0
        case .toggleBlockView:
            if !showingBlock {
                if schemeNode.repeats == .none {
                    schemeNode.repeats = .block(block: SchemeRepeat.Block())
                }
                
                self.resetModifiers()
                self.showingBlock = true
            }
            else {
                
                focus?.subtoken = 0
                self.resetModifiers()
                self.showingBlock = false
            }
        case .disableBlock:
            schemeNode.state = [schemeNode.state.first ?? 0]
            schemeNode.repeats = .none
            self.showingBlock = false
            focus?.subtoken = 0
        case .indent:
            self.indent()
        case .deindent:
            self.deindent()
        default:
            break
        }
    }
    
    func indent() {
        self.envState.writeBinding(binding: $schemeNode.indentation, newValue: schemeNode.indentation + 1)
    }
    
    func deindent() {
        self.envState.writeBinding(binding: $schemeNode.indentation, newValue: max(0, schemeNode.indentation - 1))
    }
}

struct TreeFocusToken: Hashable {
    let uuid: UUID?
    var subtoken: Int
}

struct Tree: View {
    @FocusState var keyFocus: TreeFocusToken?
    @State var keyBuffer = ""
    @Binding var scheme: SchemeState
    
    func insertNewEditor() -> SchemeItem {
        let ret = blankEditor(self.keyBuffer)
        scheme.schemes.append(ret)
        return ret
    }
    
    var body: some View {
        // allows standard editing configuration
        VStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array($scheme.schemes.enumerated()), id: \.element.id) { i, s in
                            ItemEditor(focus: $keyFocus,
                                       prevFocus: TreeFocusToken(uuid: scheme.schemes[max(i - 1, 0)].id, subtoken: 0),
                                       nextFocus: TreeFocusToken(uuid: scheme.schemes[min(i + 1, scheme.schemes.count - 1)].id, subtoken: 0),
                                       schemeNode: s,
                                       allNodes: $scheme.schemes)
                                .zIndex(Double(scheme.schemes.count - i)) // proper popover display
                                .padding(.leading, CGFloat(s.wrappedValue.indentation) * 20)
                        }
                    }
                    .id(0)
                }
                .onAppear {
                    reader.scrollTo(0, anchor: .bottom)
                }
                .padding(.trailing, 4)
                .padding(.vertical, 10)
            }
            
            TextField("template", text: $keyBuffer)
                .textFieldStyle(.plain)
                .padding(6)
                .background {
                    BackgroundView()
                }
                .shadow(radius: 4)
                .padding(10)
                .focused($keyFocus, equals: TreeFocusToken(uuid: nil, subtoken: 0))
                .onSubmit {
                    keyFocus = TreeFocusToken(uuid: self.insertNewEditor().id, subtoken: 0)
                    keyBuffer = ""
                }
        }
        .onTapGesture {
            self.keyFocus = TreeFocusToken(uuid: nil, subtoken: 0)
        }
    }
}

struct Tree_Previews: PreviewProvider {
    static var previews: some View {
        Tree(scheme: .constant(debugSchemes[0]))
    }
}
