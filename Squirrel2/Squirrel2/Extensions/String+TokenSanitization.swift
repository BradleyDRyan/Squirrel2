//
//  String+TokenSanitization.swift
//  Squirrel2
//
//  Helper to sanitize Firebase tokens for HTTP headers
//

import Foundation

extension String {
    /// Sanitizes a token for use in HTTP headers by removing invalid characters
    var sanitizedForHTTPHeader: String {
        // First trim whitespace and newlines
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Then filter to only ASCII characters to avoid encoding issues
        let asciiOnly = trimmed.filter { $0.isASCII }
        
        return asciiOnly
    }
}