//
//  Tree.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/13/23.
//

import SwiftUI
import SwiftUIIntrospect

//not the greatest conventions overall, fix!

fileprivate let defaultStartOffset: TimeInterval = 9 * .hour
fileprivate let defaultEndOffset: TimeInterval = 23 * .hour

fileprivate func standardStart() -> Date {
    .now.startOfDay() + defaultStartOffset
}

fileprivate func standardEnd() -> Date {
    .now.startOfDay() + defaultEndOffset
}

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

#if os(macOS)
fileprivate let digitWidth: CGFloat = 7.5
#else
fileprivate let digitWidth: CGFloat = 11
#endif
struct ItemEditor: View {
    @FocusState.Binding var focus: TreeFocusToken?
    
    @Binding var schemeNode: SchemeItem
    @Binding var allNodes: [SchemeItem]
    
    @EnvironmentObject var envState: EnvState
    
    @EnvironmentObject var menuDispatcher: MenuState
    @State var showingModifierPopover = false
    @State var showingStart = false
    @State var showingEnd   = false
    @State var showingBlock = false
    
    @State var startTimeComponent: Calendar.Component? = nil
    @State var startTimeBuffer: String? = nil
    @State var startTimeSettled = 0 // swiftui bug of selection not being proper
    
    @State var endTimeComponent: Calendar.Component? = nil
    @State var endTimeBuffer: String? = nil
    @State var endTimeSettled = 0 // swiftui bug of selection not being proper
   
    func reallySet(_ comp: Calendar.Component, value: Int, date: Date) -> Date {
        var components = NSCalendar.current.dateComponents([.minute, .hour, .day, .month, .year], from: date)
        components.setValue(value, for: comp)
        return NSCalendar.current.date(from: components)!
    }
    
    func field(date: Binding<Date?>, timeBuffer: Binding<String?>, timeComponent: Binding<Calendar.Component?>, timeSettled: Binding<Int>, fFocus: Int, comp: Calendar.Component) -> some View {
        func write(comp: Calendar.Component?) {
            guard let comp = comp, let timeBuffer = timeBuffer.wrappedValue, let dateVal = date.wrappedValue else {
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
            
            date.wrappedValue = newVal
        }
        
        let digits = digitMap[comp]!
        let raw = String(format: "%0\(digits)d", NSCalendar.current.component(comp, from: date.wrappedValue ?? Date.now))
        
        return TextField("", text: Binding(
            get: {
                if self.focus?.uuid == self.schemeNode.id && timeSettled.wrappedValue == self.focus?.subtoken && timeSettled.wrappedValue == fFocus && timeBuffer.wrappedValue != nil {
                    return timeBuffer.wrappedValue!
                }
                else {
                    return raw
                }
            }, set: { newValue in
                if self.focus?.uuid == self.schemeNode.id && self.focus?.subtoken == fFocus {
                    timeBuffer.wrappedValue = String(
                        newValue
                        .filter { $0.isNumber }
                        .suffix(digits)
                    )
                }
            }))
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .focused(self.$focus, equals: TreeFocusToken(uuid: self.schemeNode.id, subtoken: fFocus))
                .frame(maxWidth: CGFloat(digits) * digitWidth)
                .onAppear {
                    timeComponent.wrappedValue = nil
                }
                .onChange(of: self.focus) { [focus] mf in
                    if focus?.subtoken == fFocus {
                        write(comp: timeComponent.wrappedValue)
                    }
                    if mf?.subtoken == fFocus {
                        // NOTE: cannot be cached with other string
                        // since may have changed as result of write
                        let current = String(format: "%0\(digits)d", NSCalendar.current.component(comp, from: date.wrappedValue ?? Date.now))
                        timeBuffer.wrappedValue = current
                        timeComponent.wrappedValue = comp
                        timeSettled.wrappedValue = fFocus
                    }
                }
                .onDisappear {
                    if let comp = timeComponent.wrappedValue {
                        write(comp: comp)
                    }
                    timeComponent.wrappedValue = nil
                    timeBuffer.wrappedValue = nil
                }
                .onSubmit {
                    write(comp: comp)
                    
                    self.focus?.subtoken = fFocus + 1
                }
    }
    
    func dateEditor(_ label: String, date: Binding<Date?>, timeBuffer: Binding<String?>, timeComponent: Binding<Calendar.Component?>, timeSettled: Binding<Int>, offset: Int) -> some View {
        HStack {
            #if os(macOS)
            Text(label)
                .font(.body.bold())
            #endif
            
            HStack(spacing: 0) {
                //YYYY
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, timeSettled: timeSettled, fFocus: 1 + offset, comp: .year)
                Text("/")
                    .padding(.leading, 2)
               
                //MM
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, timeSettled: timeSettled, fFocus: 2 + offset, comp: .month)
                Text("/")
                    .padding(.leading, 2)
               
                //DD
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, timeSettled: timeSettled, fFocus: 3 + offset, comp: .day)
            }
            .monospaced()
            .blueBackground()
            
            Text("at")
            
            HStack(spacing: 0) {
                //HH
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, timeSettled: timeSettled, fFocus: 4 + offset, comp: .hour)
                Text(":")
                
                //MM
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, timeSettled: timeSettled, fFocus: 5 + offset, comp: .minute)
            }
            .monospaced()
            .blueBackground()
        }
        .textFieldStyle(.plain)
        .onAppear {
            self.focus?.subtoken = 3
        }
    }
   
    @State private var blockBuffer = ""
    
    func blockEditor(_ label: String, schemeRepeat: Binding<SchemeRepeat>, offset: Int) -> some View {
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
                #if os(macOS)
                Text(label)
                    .font(.body.bold())
                    .padding(.trailing, 4)
                #endif
                
                Text("remainders")
                TextField("", text: Binding(get: {
                    blockBuffer
                }, set: { str in
                    blockBuffer = str.filter {$0.isNumber || $0 == ","}
                    blockBinding.wrappedValue.remainders = blockBuffer
                        .split(separator: ",")
                        .map { Int($0) ?? 0 }
                }))
                    .focused($focus, equals: TreeFocusToken(uuid: schemeNode.id, subtoken: 1 + offset))
                    .frame(maxWidth: 60)
                    .blueBackground()
                    .padding(.trailing, 4)
                
                Text("blocks")
                TextField("", text: Binding(digits: blockBinding.blocks, min: 1, max: SchemeRepeat.Block.maxBlocks))
                    .focused($focus, equals: TreeFocusToken(uuid: schemeNode.id, subtoken: 2 + offset))
                    .frame(maxWidth: 20)
                    .blueBackground()
                    .padding(.trailing, 4)
                
                Text("mod")
                TextField("", text: Binding(digits: blockBinding.modulus, min: 1))
                    .focused($focus, equals: TreeFocusToken(uuid: schemeNode.id, subtoken: 3 + offset))
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
                if schemeRepeat.wrappedValue != .none {
                    blockBinding.wrappedValue.remainders = Array(Set(
                        blockBuffer
                            .split(separator: ",")
                            .map { min(blockBinding.wrappedValue.modulus - 1, max(Int($0) ?? 0, 0)) }
                    )).sorted()
                }
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
                    self.dateEditor("Starts", date: $schemeNode.start, timeBuffer: $startTimeBuffer, timeComponent: $startTimeComponent, timeSettled: $startTimeSettled, offset: 0)
                }
                
                if showingEnd {
                    self.dateEditor("Ends", date: $schemeNode.end, timeBuffer: $endTimeBuffer, timeComponent: $endTimeComponent, timeSettled: $endTimeSettled, offset: 16)
                }
                
                if showingBlock {
                    self.blockEditor("Block Repeat", schemeRepeat: $schemeNode.repeats, offset: 32)
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
    
    var modifiersPopover: some View {
        VStack {
            Toggle("Start", isOn: Binding(get: {
                schemeNode.start != nil
            }, set: {
                schemeNode.start = $0 ? standardStart() : nil
            }))
            if schemeNode.start != nil {
                self.dateEditor("Starts", date: $schemeNode.start, timeBuffer: $startTimeBuffer, timeComponent: $startTimeComponent, timeSettled: $startTimeSettled, offset: 0)
            }
            
            Toggle("End", isOn: Binding(get: {
                schemeNode.end != nil
            }, set: {
                schemeNode.end = $0 ? standardEnd() : nil
            }))
            if schemeNode.end != nil {
                self.dateEditor("Ends", date: $schemeNode.end, timeBuffer: $endTimeBuffer, timeComponent: $endTimeComponent, timeSettled: $endTimeSettled, offset: 16)
            }
           
            Toggle("Block", isOn: Binding(get: {
                return schemeNode.repeats != .none
            }, set: { enabled in
                schemeNode.repeats = enabled ? .block(block: .init()) : .none
            }))
            if schemeNode.repeats != .none {
                self.blockEditor("Block Repeat", schemeRepeat: $schemeNode.repeats, offset: 32)
            }
            
            Spacer()
        }
        .padding(12)
        .background {
            Color.clear
                .onTapGesture {
                    self.focus = nil
                }
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
    
    @State var test = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                if schemeNode.state.allSatisfy({ $0 == -1 }) {
                    Button {
                        if schemeNode.state.count == 1 {
                            schemeNode.state[0] = 0
                        }
                    } label: {
                        Image(systemName: "checkmark.square")
                            .resizable()
                            .opacity(0.7)
                            .frame(width: 17, height: 17)
                    }
                    .buttonStyle(.plain)
                    
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
                            .frame(width: 17, height: 17)
                    }
                    .buttonStyle(.plain)

                    // disabled doesn't look nice
                    
#warning("TODO, see if we can get the nsviewrepresntable actually working. Seems rather difficult. If so, do proper enter + up/down navigation")
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("", text: $schemeNode.text)
                            .focused($focus, equals: TreeFocusToken(uuid: schemeNode.id, subtoken: 0))
                            .textFieldStyle(.plain)
                            .onSubmit {
                                #if os(macOS)
                                if NSEvent.modifierFlags.contains(.shift) {
                                    shiftEnter()
                                }
                                else {
                                    enter()
                                }
                                #else
                                enter()
                                #endif
                            }
                        
                        self.captions
                    }
                }
                
                #if os(iOS)
                if focus?.uuid == self.schemeNode.id {
                    Button("Time") {
                        showingModifierPopover = true
                    }
                }
                #endif
            }
            .background {
                Color.clear
                    .onTapGesture {
                        self.focus = TreeFocusToken(uuid: schemeNode.id, subtoken: 0)
                    }

            }
            
            #if os(macOS)
            if self.anyModifiers && focus?.uuid == self.schemeNode.id {
                Color.clear
                    .frame(maxHeight: 0)
                    .overlay(alignment: .top) {
                        self.modifiers
                    }
            }
            #else
            Color.clear
                .frame(maxHeight: 0)
                .sheet(isPresented: $showingModifierPopover) {
                    self.modifiersPopover
                }
            #endif
        }
        //hm surely there's a less symmetric way...
        .onReceive(menuDispatcher, perform: self.handleMenuAction(_:))
        #if os(macOS)
        .onExitCommand {
            focus = TreeFocusToken(uuid: schemeNode.id, subtoken: 0)
            resetModifiers()
        }
        #else
        .swipeActions(edge: .trailing) {
            Button("Deindent") {
                deindent()
            }
            
            Button("Delete", role: .destructive) {
                delete()
            }
        }
        .swipeActions(edge: .leading) {
            Button("Indent") {
                indent()
            }
        }

        #endif
        .onChange(of: focus) { newFocus in
            if newFocus?.uuid != self.schemeNode.id {
                resetModifiers()
            }
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
                    schemeNode.start = standardStart()
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
                    schemeNode.end = standardEnd()
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
        case .delete:
            self.delete()
        default:
            break
        }
    }
    
    func indent() {
        schemeNode.indentation += 1
    }
    
    func deindent() {
        schemeNode.indentation = max(0, schemeNode.indentation - 1)
    }
    
    func enter() {
        guard let myIndex = allNodes.firstIndex(of: schemeNode) else {
            return
        }
    
        let editor = blankEditor("", indentation: schemeNode.indentation)
        allNodes.insert(editor, at: myIndex + 1)
        focus = TreeFocusToken(uuid: editor.id, subtoken: 0)
    }
    
    func shiftEnter() {
        guard let myIndex = allNodes.firstIndex(of: schemeNode) else {
            return
        }
    
        let editor = blankEditor("", indentation: schemeNode.indentation)
        allNodes.insert(editor, at: myIndex)
        focus = TreeFocusToken(uuid: editor.id, subtoken: 0)
    }
    
    func delete() {
        guard let myIndex = allNodes.firstIndex(of: schemeNode) else {
            return
        }
        #warning("TODO swiftui bug?")
        if myIndex == allNodes.count - 1 {
            return
        }
       
        DispatchQueue.main.async {
            focus = allNodes.count == 1 ? nil : TreeFocusToken(uuid: allNodes[max(myIndex - 1, 0)].id, subtoken: 0)
            allNodes.remove(at: myIndex)
        }
    }
}

struct TreeFocusToken: Hashable {
    let uuid: UUID?
    var subtoken: Int
}

struct Tree: View {
    @EnvironmentObject var env: EnvState
    @FocusState var keyFocus: TreeFocusToken?
    @State var keyBuffer = ""
    @Binding var scheme: SchemeState
    @State var buffer: SchemeState
    
    init(scheme: Binding<SchemeState>) {
        _scheme = scheme
        _buffer = State(initialValue: scheme.wrappedValue)
    }
    
    func insertNewEditor() -> SchemeItem {
        let ret = blankEditor(self.keyBuffer)
        scheme.schemes.append(ret)
        return ret
    }
    
    var content: some View {
        #if os(macOS)
        ForEach(Array($scheme.schemes.enumerated()), id: \.element.id) { i, s in
            ItemEditor(focus: $keyFocus,
                       schemeNode: s,
                       allNodes: $scheme.schemes)
            .zIndex(Double(scheme.schemes.count - i)) // proper popover display
            .padding(.leading, CGFloat(s.wrappedValue.indentation) * 20)
            .id(i)
        }
        #else
        //buffer on iOS for spped
        ForEach(Array($buffer.schemes.enumerated()), id: \.element.id) { i, s in
            ItemEditor(focus: $keyFocus,
                       schemeNode: s,
                       allNodes: $buffer.schemes)
            .zIndex(Double(buffer.schemes.count - i)) // proper popover display
            .padding(.leading, CGFloat(s.wrappedValue.indentation) * 20)
            .id(i)
        }
        #endif
    }
    
    var hostedContent: some View {
        #if os(macOS)
        ScrollView {
            VStack(spacing: 4) {
                content
            }

        }
        .onTapGesture {
            self.keyFocus = TreeFocusToken(uuid: nil, subtoken: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        #else
        List {
            content
        }
//        .listStyle(.plain)
        #endif
    }
        
    var body: some View {
        // allows standard editing configuration
        VStack {
            if env.scheme == scheme.id {
                ScrollViewReader { reader in
                    self.hostedContent
                        .onAppear {
                            reader.scrollTo(scheme.schemes.count - 1)
                        }
                        .onChange(of: scheme.id) { _ in
                            reader.scrollTo(scheme.schemes.count - 1)
                        }
                    
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
        }
        .background {
            Color.clear
                .onTapGesture {
                    self.keyFocus = TreeFocusToken(uuid: nil, subtoken: 0)
                }
        }
        #if os(iOS)
        .onChange(of: buffer) { buff in
            DispatchQueue.main.async {
                scheme = buff
            }
        }
        #endif
    }
}

struct Tree_Previews: PreviewProvider {
    static var previews: some View {
        Tree(scheme: .constant(debugSchemes[0]))
    }
}
