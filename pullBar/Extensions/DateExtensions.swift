//
//  DateExtensions.swift
//  pullBar
//
//  Created by Pavel Makhov on 2021-11-21.
//

import Foundation

extension Date {
    
    func getElapsedInterval() -> String {
        
        let interval = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: self, to: Date())

        if let year = interval.year, year > 0 {
            return "\(year)y"
        } else if let month = interval.month, month > 0 {
            return "\(month)mo"
        } else if let day = interval.day, day > 0 {
            return "\(day)d"
        } else if let hour = interval.hour, hour > 0 {
            return "\(hour)h"
        } else if let minute = interval.minute, minute > 0 {
            return "\(minute)m"
        } else {
            return "now"
        }
        
    }
}
