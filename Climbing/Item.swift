//
//  Item.swift
//  Climbing
//
//  Created by Sinnus Wong on 12/24/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
