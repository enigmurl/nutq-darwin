//
//  Time.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 7/4/23.
//

import Foundation

extension TimeInterval {
    static var minute: TimeInterval {
        60
    }
    
    static var hour: TimeInterval {
        3600
    }
    
    static var day: TimeInterval {
        86400
    }
    
    static var week: TimeInterval {
        604800
    }
}

// a bit redundant, but should be fine
extension Date {
    var dateString: String {
        let diff = dayDifference(with: .now)
        
        let day: String
        if diff == 0 {
            day = "Today"
        }
        else if diff == 1 {
            day = "Tomorrow"
        }
        else if diff < 7 {
            day = weekdayFormatter.string(from: self)
        }
        else {
            day = dayFormatter.string(from: self)
        }
        
        let time = hourFormatter.string(from: self)
        
        return day + " " + time
    }
    
    var timeString: String {
        hourFormatter.string(from: self)
    }
    
    // time interval starts at midnight
    func dayDifference(with date: Date) -> Int {
        let cal = NSCalendar.current
        let ourStart = cal.startOfDay(for: self)
        let theirStart = cal.startOfDay(for: date)
        
        return Int(ourStart.timeIntervalSince(theirStart) / .day)
    }
    
    func startOfDay() -> Date {
        NSCalendar.current.startOfDay(for: self)
    }
}

let dayFormatter = {
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "MMMM dd"
    return dayFormatter
}()

let weekdayFormatter = {
    let weekFormatter = DateFormatter()
    weekFormatter.dateFormat = "EEEE"
    return weekFormatter
}()

let monthFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM"
    return formatter
}()

let hourFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

//use march since it has 31 days, some date in the past
let referenceDate = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    dateFormatter.timeZone = TimeZone.current
    dateFormatter.locale = Locale.current
    return dateFormatter.date(from: "2000-03-14T12:00:00")!
}()
