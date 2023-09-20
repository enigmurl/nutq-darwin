//
//  nutqdarwinApp.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 5/28/23.
//

import SwiftUI
import GoogleSignIn
import UserNotifications

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    var env: EnvState!
  
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02hhx", $0) }.joined()
        Task.init {
            env.registered = await auth_void_request(env: env, "/sync/device/\(token)", method: "POST")
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        env.manager.force {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .seconds(5))) {
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
    }
    
   
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02hhx", $0) }.joined()
        Task.init {
            env.registered = await auth_void_request(env: env, "/sync/device/\(token)", method: "POST")
        }
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
    
    @State var skippedFirstAppear = false
    
    fileprivate let notifDelegate = NotificationDelegate()
    
    func commandMenu(menuAction: MenuAction, key: KeyEquivalent, modifiers: EventModifiers = []) -> some View {
        Button(menuAction.description) {
            commandDispatcher.send(menuAction)
        }
        .keyboardShortcut(key, modifiers: modifiers.union(.command))
    }
    
    func notificationSetup() {
        if !env.registered {
#if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
#else
            NSApplication.shared.registerForRemoteNotifications()
#endif
        }

        
        notifDelegate.registerLocal()
    }

    var body: some Scene {
        WindowGroup {
            NutqContentView()
                .environmentObject(env)
                .environmentObject(commandDispatcher)
                .onAppear {
                    self.appDelegate.env = env
                    self.notificationSetup()
                }
            #if os(iOS)
                .onChange(of: phase, initial: false) { (phase, newPhase) in
                    if newPhase == .inactive {
                        self.env.manager.force {}
                    }
                    else if newPhase == .active {
                        self.env.stealSlave()
                    }
                }
            #else
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    if !skippedFirstAppear {
                        skippedFirstAppear = true
                    }
                    else {
                        self.env.stealSlave()
                    }
                }
            #endif
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Group {
                    self.commandMenu(menuAction: .gotoUnion, key: "u")
                    self.commandMenu(menuAction: .prevScheme, key: "[")
                    self.commandMenu(menuAction: .nextScheme, key: "]")
                    self.commandMenu(menuAction: .toggle, key: "f")
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

fileprivate class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func registerLocal() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { (_, _) in }
        center.delegate = self
        
        let complete = UNNotificationAction(identifier: "complete", title: "Complete", options: [.foreground])
        let remind15Minute = UNNotificationAction(identifier: "remind-0", title: "Remind in 10 minutes", options: [])
        let remindOneHour = UNNotificationAction(identifier: "remind-1", title: "Remind in 60 minutes", options: [])
        let remindNight = UNNotificationAction(identifier: "remind-2", title: "Remind me tonight", options: [.destructive])
        let remindTomorrowMorning = UNNotificationAction(identifier: "remind-3", title: "Remind me tomorrow morning", options: [])
        let remindTomorrow = UNNotificationAction(identifier: "remind-4", title: "Remind in 24 hours", options: [])
        let remindWeek = UNNotificationAction(identifier: "remind-5", title: "Remind in 7 days", options: [])
        
        let main = UNNotificationCategory(identifier: "nutq-reminder", actions: [complete, remind15Minute, remindOneHour, remindNight, remindTomorrowMorning, remindTomorrow, remindWeek], intentIdentifiers: [], options: [.hiddenPreviewsShowSubtitle, .hiddenPreviewsShowTitle])
        UNUserNotificationCenter.current().setNotificationCategories([main])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
    
    struct SchemePath: Codable {
        let index: Int
        let scheme_id: UUID
        let item_id: UUID
    }
    
    struct DateHolder: Codable {
        let dispatch_time: Date
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["nutq_path"] as? [String: Any] else {
            return
        }
        
        guard let time = response.notification.request.content.userInfo["nutq_time"] as? [String: Any] else {
            return
        }
        
        let env = EnvMiniState()
        
        let index = path["index"] as! Int
        let scheme_id = UUID(uuidString: path["scheme_id"] as! String)!
        let item_id = UUID(uuidString: path["item_id"] as! String)!
       
        let json_time = try? JSONSerialization.data(withJSONObject: time)
        let dispatch_time = json_time == nil ? nil : try? JSONDecoder().decode(DateHolder.self, from: json_time!)
        let delay = (dispatch_time?.dispatch_time ?? .now).distance(to: .now)
        
        let command: String
        let arg_path = "\(scheme_id)/\(item_id)/\(index)"
        let body: Data?
        
        if response.actionIdentifier == "complete" {
            command = "/sync/nutq/complete/"
            body = nil
        }
        else {
            command = "/sync/nutq/delay/"
            
            let time: TimeInterval
            if response.actionIdentifier == "remind-0" {
                time = .minute * 10 + delay
            }
            else if response.actionIdentifier == "remind-1" {
                time = .minute * 60 + delay
            }
            else if response.actionIdentifier == "remind-2" {
                // tonight
                time = max(.minute, Date.now.distance(to: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now))
            }
            else if response.actionIdentifier == "remind-3" {
                // tomorrow morning
                time = max(.minute, Date.now.distance(to: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now + .day) ?? .now))
            }
            else if response.actionIdentifier == "remind-4" {
                time = .day + delay
            }
            else if response.actionIdentifier == "remind-5" {
                time = .week + delay
            }
            else {
                time = .minute + delay
            }
            
            body = "\(time)".data(using: .utf8)
        }
       
        Task.init {
            let success = await auth_void_request(env: env, command + arg_path, body: body, method: "PUT")
            
            if !success {
                spawnErrorNotification(command)
            }
        }
    }
    
    func spawnErrorNotification(_ path: String) {
        let content = UNMutableNotificationContent()
        content.title = "Error Notification"
        content.body = "An error occurred while performing " + path

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: "errorNotification", content: content, trigger: trigger)
        
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request) { _ in }
    }
}
