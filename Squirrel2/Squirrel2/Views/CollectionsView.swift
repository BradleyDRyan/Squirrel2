//
//  CollectionsView.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth

struct CollectionsView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var viewModel = CollectionsViewModel()
    @State private var selectedCollection: Collection?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                } else if viewModel.collections.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Collections Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Create collections to organize your entries")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(viewModel.collections) { collection in
                            NavigationLink(destination: CollectionDetailView(collection: collection)) {
                                CollectionCard(collection: collection)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            if let userId = firebaseManager.currentUser?.uid {
                viewModel.startListening(userId: userId)
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }
}

struct CollectionCard: View {
    let collection: Collection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(collection.icon)
                    .font(.system(size: 32))
                
                Spacer()
                
                if collection.entryCount > 0 {
                    Text("\(collection.entryCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Text(collection.name)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if !collection.instructions.isEmpty {
                Text(collection.instructions)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color(hex: collection.color).opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: collection.color).opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

// Color(hex:) extension is defined in DesignSystem/Colors.swift
