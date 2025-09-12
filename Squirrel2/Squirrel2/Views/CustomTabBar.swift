//
//  CustomTabBar.swift
//  Squirrel2
//
//  Custom tab bar component for animated transitions
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selection: Int
    
    var body: some View {
        HStack(spacing: 0) {
            TabBarButton(
                icon: "checklist",
                title: "Tasks",
                isSelected: selection == 0
            ) {
                selection = 0
            }
            
            TabBarButton(
                icon: "photo.fill",
                title: "Photos",
                isSelected: selection == 1
            ) {
                selection = 1
            }
            
            TabBarButton(
                icon: "folder.fill",
                title: "Collections",
                isSelected: selection == 2
            ) {
                selection = 2
            }
        }
        .frame(height: 49)
        .background(
            Color.primaryBackground
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: -0.5)
        )
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundColor(isSelected ? .squirrelPrimary : .gray)
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}