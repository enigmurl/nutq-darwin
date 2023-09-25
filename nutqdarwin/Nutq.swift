//
//  nutqdarwinApp.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 5/28/23.
//

import SwiftUI
import GoogleSignIn
import FirebaseCore
import FirebaseMessaging
import UserNotifications

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate, MessagingDelegate {
    var env: EnvState!
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NotificationDelegate.shared.registerLocal()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }
 
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
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
    
    
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        self.refresh()
    }
}
#else
class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate {
    var env: EnvState!
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        NotificationDelegate.shared.registerLocal()
        return true
    }
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        return true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        
    }
   
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) async -> UIBackgroundFetchResult {
        // update
        self.refresh()
        
        return .newData
    }
}
#endif

extension AppDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            Task.init {
                await auth_void_request(env: env, "/sync/device/\(token)", method: "POST")
            }
        }
    }
    
    func refresh() {
        if let e = EnvState.shared, e.slaveState == .write {
            e.manager.notificationControl()
        }
        else {
            let env = EnvMiniState()
            env.retrieve { res in
                if res != nil {
                    env.manager.notificationControl()
                }
            }
        }
    }
}

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
    
    func commandMenu(menuAction: MenuAction, key: KeyEquivalent, modifiers: EventModifiers = []) -> some View {
        Button(menuAction.description) {
            commandDispatcher.send(menuAction)
        }
        .keyboardShortcut(key, modifiers: modifiers.union(.command))
    }
    
    func notificationSetup() {
        // not using anymore
#if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
#else
        NSApplication.shared.registerForRemoteNotifications()
#endif        
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
                    if newPhase == .inactive || newPhase == .background {
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

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
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
    
    
    func spawn_notif(title: String, body: String, scheme_id: Any, item_id: Any, index: Any) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = [
            "scheme_id": scheme_id,
            "item_id": item_id,
            "index": index
        ]
        content.categoryIdentifier = "nutq-reminder"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: "nutq_reminder " + (item_id as! String), content: content, trigger: trigger)
        
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request) { _ in }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    struct DateHolder: Codable {
        let dispatch_time: Date?
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let user_info = response.notification.request.content.userInfo
        
        guard let scheme_id_ = user_info["scheme_id"] as? String,
              let item_id_   = user_info["item_id"] as? String,
              let index_     = user_info["index"] as? String else {
            return
        }
        
        let env = EnvMiniState()
        
        let index = Int(index_, radix: 10)!
        let scheme_id = UUID(uuidString: scheme_id_)!
        let item_id = UUID(uuidString: item_id_)!
       
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
                time = .minute * 10
            }
            else if response.actionIdentifier == "remind-1" {
                time = .minute * 60
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
                time = .day
            }
            else if response.actionIdentifier == "remind-5" {
                time = .week
            }
            else {
                return
            }
           
            body = try? JSONEncoder().encode(DateHolder(dispatch_time: .now + time))
        }
       
        let success = await auth_void_request(env: env, command + arg_path, body: body, method: "PUT")
        
        if !success {
            spawnErrorNotification(command)
        }
    }
    
    func spawnErrorNotification(_ path: String) {
        let content = UNMutableNotificationContent()
        content.title = "Error Notification"
        content.body = "An error occurred while performing " + path

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request) { _ in }
    }
}
