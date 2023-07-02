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

fileprivate func blankEditor(_ str: String) -> SchemeItem {
    return SchemeItem(state: [0], text: str, repeats: .none, children: [])
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

#if false
fileprivate struct ItemTextField: NSViewRepresentable {
    @Binding var text: String
    
}
#else
fileprivate struct ItemTextField: View {
    @Binding var text: String
    var body: some View {
        TextField("", text: $text)
    }
}
#endif


//use march since it has 31 days, some date in the past
fileprivate let referenceDate = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    dateFormatter.timeZone = TimeZone.current
    dateFormatter.locale = Locale.current
    return dateFormatter.date(from: "2000-03-15T12:00:00")!
}()

fileprivate let digitMap: [Calendar.Component: Int] = [.minute: 2, .hour: 2, .day: 2, .month: 2, .year: 4]
fileprivate let minMap: [Calendar.Component: Int] = [.minute: 0, .hour: 0, .day: 1, .month: 1, .year: 1]
fileprivate let maxMap: [Calendar.Component: Int] = [.minute: 59, .hour: 23, .day: 31, .month: 12, .year: 9999]

struct ItemEditor: View {
    @FocusState var mainFocus: Int?
    @Binding var schemeNode: SchemeItem
    var parentArray: Binding<[SchemeItem]>?
    @Binding var allNodes: [SchemeItem]
    
    @EnvironmentObject var envState: EnvState
    
    @EnvironmentObject var menuDispatcher: MenuState
    @State var showingStart = false
    @State var showingEnd   = false
    @State var showingBlock = false
    
    let initialFocus: Int?
    
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
        
        return TextField("", text: Binding(get: {
                 mainFocus == focus && timeBuffer != nil && timeSettled == mainFocus ? timeBuffer! : raw
            }, set: { newValue in
                if mainFocus == focus {
                    timeBuffer = String(
                        newValue
                        .filter { $0.isNumber }
                        .suffix(digits)
                    )
                }
            }))
                .multilineTextAlignment(.trailing)
                .focused($mainFocus, equals: focus)
                .frame(maxWidth: CGFloat(digits) * 7.5)
                .onAppear {
                    timeComponent = nil
                }
                .onChange(of: mainFocus) { mf in
                    if mf == focus {
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
                    mainFocus = focus + 1
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
            mainFocus = 0
            self.resetModifiers()
        }
        .onAppear {
            mainFocus = 3
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
                    .focused($mainFocus, equals: 1)
                    .frame(maxWidth: 60)
                    .blueBackground()
                    .padding(.trailing, 4)
                
                Text("blocks")
                TextField("", text: Binding(digits: blockBinding.blocks, min: 1, max: SchemeRepeat.Block.maxBlocks))
                    .focused($mainFocus, equals: 2)
                    .frame(maxWidth: 20)
                    .blueBackground()
                    .padding(.trailing, 4)
                
                Text("modulus")
                TextField("", text: Binding(digits: blockBinding.modulus, min: 1))
                    .focused($mainFocus, equals: 3)
                    .frame(maxWidth: 20)
                    .blueBackground()
                    .padding(.trailing, 2)

                Text("(days)")
                    .font(.caption2.lowercaseSmallCaps())
            }
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .onAppear {
                mainFocus = 1
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
                mainFocus = 0
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
                        TextField("", text: $schemeNode.text)
                            .focused($mainFocus, equals: 0)
                            .textFieldStyle(.plain)
                            .onAppear {
                                self.mainFocus = initialFocus
                            }
                        
                        self.captions
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(Array($schemeNode.children.enumerated()), id: \.element.id) { i, scheme in
                    ItemEditor(schemeNode: scheme, parentArray: $allNodes, allNodes: $schemeNode.children, initialFocus: nil)
                        .zIndex(Double(schemeNode.children.count - i)) // proper popover display
                }
                .padding(.leading, 25)
            }
           
            if self.anyModifiers && mainFocus != nil {
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
        .onChange(of: mainFocus) { focus in
            if focus == nil {
                resetModifiers()
            }
        }
    }
    
    func handleMenuAction(_ action: MenuAction) {
        guard mainFocus != nil else {
            return
        }
        
        switch (action) {
        case .toggleStartView:
            if !showingStart {
                if schemeNode.start == nil {
                    schemeNode.start = .now.startOfDay() + defaultStartOffset
                }
               
                mainFocus = 0
                self.resetModifiers()
                self.showingStart = true
            }
            else {
                
                mainFocus = 0
                self.resetModifiers()
                self.showingStart = false
            }
        case .disableStart:
            schemeNode.start = nil
            self.showingStart = false
            mainFocus = 0
        case .toggleEndView:
            if !showingEnd {
                if schemeNode.end == nil {
                    schemeNode.end = .now.startOfDay() + defaultEndOffset
                }
                
                mainFocus = 0
                self.resetModifiers()
                self.showingEnd = true
            }
            else {
                
                mainFocus = 0
                self.resetModifiers()
                self.showingEnd = false
            }
        case .disableEnd:
            schemeNode.end = nil
            self.showingEnd = false
            mainFocus = 0
        case .toggleBlockView:
            if !showingBlock {
                if schemeNode.repeats == .none {
                    schemeNode.repeats = .block(block: SchemeRepeat.Block())
                }
                
                mainFocus = 0
                self.resetModifiers()
                self.showingBlock = true
            }
            else {
                
                mainFocus = 0
                self.resetModifiers()
                self.showingBlock = false
            }
        case .disableBlock:
            schemeNode.state = [schemeNode.state.first ?? 0]
            schemeNode.repeats = .none
            self.showingBlock = false
            mainFocus = 0
        case .indent:
            self.indent()
        case .deindent:
            self.deindent()
        default:
            break
        }
    }
    
    func indent() {
       // can only indent if we're not the first child
        guard let index = allNodes.firstIndex(of: self.schemeNode), index != 0 else {
            return
        }
        
        // append to previous node's children, and remove from current level
        var allNodesCopy = allNodes
        var previousNodeChildren = allNodes[index - 1].children
        
        allNodesCopy.remove(at: index)
        previousNodeChildren.append(schemeNode)
        
        self.envState.writeBinding(binding: $allNodes, newValue: allNodesCopy)
        self.envState.writeBinding(binding: $allNodes[index - 1].children, newValue: previousNodeChildren)
    }
    
    func deindent() {
        guard let parentArray = parentArray,
              let parentIndex = parentArray.firstIndex(where: {$0.wrappedValue.children == allNodes}),
              let myIndex = allNodes.firstIndex(of: self.schemeNode) else {
           return
        }
        
        // delete from allNodes
        // insert into parentArray
        // what was previously in front of us are now our children
        // this should probably be put into a better undoable function, but copy it is....
        
        var allNodesCopy = allNodes
        var parentNodesCopy = parentArray.wrappedValue
        var myChildrenCopy = schemeNode.children
        
        allNodesCopy.remove(at: myIndex)
        myChildrenCopy.append(contentsOf: allNodesCopy.dropFirst(myIndex))
        allNodesCopy.removeLast(allNodesCopy.count - myIndex)
      
        self.envState.writeBinding(binding: $schemeNode.children, newValue: myChildrenCopy)
        
        // only update parent after schemeNode has been fully resolved
        // but before we overwrite allNodes, removing the reference to schemeNode
        parentNodesCopy.insert(schemeNode, at: parentIndex + 1)
        self.envState.writeBinding(binding: parentArray, newValue: parentNodesCopy)
        
        self.envState.writeBinding(binding: $allNodes, newValue: allNodesCopy)
    }
}

struct Tree: View {
    @FocusState var keyFocus
    #warning("TODO find better solution for focusing on new items")
    @State var showedOne = false
    @State var keyBuffer = ""
    @Binding var scheme: SchemeState
    
    func insertNewEditor() {
        scheme.schemes.append(blankEditor(self.keyBuffer))
    }
    
    var body: some View {
        // allows standard editing configuration
        VStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array($scheme.schemes.enumerated()), id: \.element.id) { i, s in
                            ItemEditor(schemeNode: s, parentArray: nil, allNodes: $scheme.schemes,
                                       initialFocus: showedOne && s.wrappedValue == scheme.schemes.last ? 0 : nil)
                                .zIndex(Double(scheme.schemes.count - i)) // proper popover display
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
                .focused($keyFocus)
                .onChange(of: scheme.id) { _ in // tree hierarchy is weird, bad fix
                    showedOne = false
                }
                .onDisappear {
                    showedOne = false
                }
                .onSubmit {
                    self.insertNewEditor()
                    
                    showedOne = true
                    keyFocus = false
                    keyBuffer = ""
                }
        }
        .onTapGesture {
            keyFocus = true
        }
    }
}

struct Tree_Previews: PreviewProvider {
    static var previews: some View {
        Tree(scheme: .constant(debugSchemes[0]))
    }
}
