//
//  nutqdarwinApp.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 5/28/23.
//

import SwiftUI

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    var env: EnvState!
    
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        env.manager.force {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        
        return .terminateLater
    }
    
}
#else
class AppDelegate: UIResponder, UIApplicationDelegate {
    var env: EnvState!
    
    func applicationWillEnterForeground(_ application: UIApplication) {
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        NSFileCoordinator.removeFilePresenter(env.document)
    }
}
#endif

@main
struct Nutq: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    @StateObject private var env = EnvState()
    @StateObject private var commandDispatcher = MenuState()
    @Environment(\.scenePhase) var phase
    
    func commandMenu(menuAction: MenuAction, key: KeyEquivalent, modifiers: EventModifiers = []) -> some View {
        Button(menuAction.description) {
            commandDispatcher.send(menuAction)
        }
        .keyboardShortcut(key, modifiers: modifiers.union(.command))
    }

    var body: some Scene {
        WindowGroup {
            NutqContentView()
                .environmentObject(env)
                .environmentObject(commandDispatcher)
                .onAppear {
                    self.appDelegate.env = env
                }
                .onChange(of: phase) { phase in
                    if phase == .inactive {
                        self.env.manager.force {}
                    }
                }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Group {
                    self.commandMenu(menuAction: .gotoUnion, key: "h")
                    self.commandMenu(menuAction: .prevScheme, key: "[", modifiers: .shift)
                    self.commandMenu(menuAction: .nextScheme, key: "]", modifiers: .shift)
                }
                
                Group {
                    self.commandMenu(menuAction: .deindent, key: "[")
                    self.commandMenu(menuAction: .indent, key: "]")
                }
                
                Group {
                    self.commandMenu(menuAction: .toggleStartView, key: "s")
                    self.commandMenu(menuAction: .disableStart, key: "s", modifiers: .shift)
                    self.commandMenu(menuAction: .toggleEndView, key: "e")
                    self.commandMenu(menuAction: .disableEnd, key: "e", modifiers: .shift)
                    self.commandMenu(menuAction: .toggleBlockView, key: "b")
                    self.commandMenu(menuAction: .disableBlock, key: "b", modifiers: .shift)
                }
            }
        }
    }
}
