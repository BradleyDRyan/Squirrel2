//
//  EntryFormat.swift
//  Squirrel2
//
//  Defines the structure and field types for collection entries
//

import Foundation

struct EntryFormat: Codable {
    let fields: [EntryField]
    let version: Int  // Track format version for future migrations
    
    init(fields: [EntryField], version: Int = 1) {
        self.fields = fields
        self.version = version
    }
}

struct EntryField: Codable {
    let key: String  // Field identifier (e.g., "title", "rating")
    let label: String  // Display name
    let type: FieldType
    let required: Bool
    let options: [String]?  // For select fields
    let min: Double?  // For number fields
    let max: Double?  // For number fields
    let multiline: Bool?  // For text fields
    let multiple: Bool?  // For select fields (multi-select)
    
    enum FieldType: String, Codable {
        case text = "text"
        case number = "number"
        case date = "date"
        case select = "select"
        case boolean = "boolean"
    }
    
    // Convenience initializers for common field types
    static func text(key: String, label: String, required: Bool = false, multiline: Bool = false) -> EntryField {
        return EntryField(
            key: key,
            label: label,
            type: .text,
            required: required,
            options: nil,
            min: nil,
            max: nil,
            multiline: multiline,
            multiple: nil
        )
    }
    
    static func number(key: String, label: String, required: Bool = false, min: Double? = nil, max: Double? = nil) -> EntryField {
        return EntryField(
            key: key,
            label: label,
            type: .number,
            required: required,
            options: nil,
            min: min,
            max: max,
            multiline: nil,
            multiple: nil
        )
    }
    
    static func date(key: String, label: String, required: Bool = false) -> EntryField {
        return EntryField(
            key: key,
            label: label,
            type: .date,
            required: required,
            options: nil,
            min: nil,
            max: nil,
            multiline: nil,
            multiple: nil
        )
    }
    
    static func select(key: String, label: String, options: [String], required: Bool = false, multiple: Bool = false) -> EntryField {
        return EntryField(
            key: key,
            label: label,
            type: .select,
            required: required,
            options: options,
            min: nil,
            max: nil,
            multiline: nil,
            multiple: multiple
        )
    }
    
    static func boolean(key: String, label: String, required: Bool = false) -> EntryField {
        return EntryField(
            key: key,
            label: label,
            type: .boolean,
            required: required,
            options: nil,
            min: nil,
            max: nil,
            multiline: nil,
            multiple: nil
        )
    }
}

// Example formats for common collection types
extension EntryFormat {
    static let movieFormat = EntryFormat(fields: [
        .text(key: "title", label: "Movie Title", required: true),
        .number(key: "rating", label: "Rating", required: true, min: 1, max: 10),
        .date(key: "watchDate", label: "Watch Date"),
        .select(key: "genre", label: "Genre", options: ["Action", "Comedy", "Drama", "Horror", "Sci-Fi", "Romance", "Documentary"], multiple: true),
        .text(key: "review", label: "Review", multiline: true),
        .boolean(key: "wouldRecommend", label: "Would Recommend")
    ])
    
    static let candleFormat = EntryFormat(fields: [
        .text(key: "name", label: "Candle Name", required: true),
        .text(key: "brand", label: "Brand"),
        .text(key: "scent", label: "Scent", required: true),
        .number(key: "rating", label: "Rating", required: true, min: 1, max: 10),
        .select(key: "throwStrength", label: "Throw Strength", options: ["Light", "Medium", "Strong"]),
        .number(key: "burnTime", label: "Burn Time (hours)"),
        .text(key: "notes", label: "Notes", multiline: true),
        .boolean(key: "repurchase", label: "Would Repurchase")
    ])
    
    static let workoutFormat = EntryFormat(fields: [
        .select(key: "type", label: "Workout Type", options: ["Strength", "Cardio", "Yoga", "HIIT", "Sports", "Other"], required: true),
        .number(key: "duration", label: "Duration (minutes)", required: true, min: 0),
        .select(key: "intensity", label: "Intensity", options: ["Light", "Medium", "Intense"]),
        .text(key: "exercises", label: "Exercises", multiline: true),
        .text(key: "notes", label: "Notes", multiline: true)
    ])
}