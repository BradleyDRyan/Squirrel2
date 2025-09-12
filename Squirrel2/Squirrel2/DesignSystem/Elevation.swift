//
//  Elevation.swift
//  Squirrel2
//
//  Design System - Elevation & Shadows
//

import SwiftUI

extension View {
    func elevation1() -> some View {
        self.shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
    
    func elevation2() -> some View {
        self.shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 3)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
    
    func elevation3() -> some View {
        self.shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}