//
//  CollectionDetailView.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth

struct CollectionDetailView: View {
    let collection: Collection
    @StateObject private var viewModel: CollectionDetailViewModel
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    init(collection: Collection) {
        self.collection = collection
        self._viewModel = StateObject(wrappedValue: CollectionDetailViewModel(collectionId: collection.id))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Collection Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(collection.icon)
                            .font(.system(size: 48))
                        
                        Spacer()
                        
                        Text("\(viewModel.entries.count) entries")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(collection.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    if let rules = collection.rules {
                        // Show keywords as tags
                        if !rules.keywords.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(rules.keywords.prefix(5), id: \.self) { keyword in
                                        Text(keyword)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color(hex: collection.color).opacity(0.2))
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(hex: collection.color).opacity(0.05))
                .cornerRadius(16)
                
                // Entries List
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if viewModel.entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("No entries yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Say \"\(collection.name): \" followed by your entry to add content here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.entries) { entry in
                            EntryCard(entry: entry, collectionColor: collection.color)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
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

struct EntryCard: View {
    let entry: Entry
    let collectionColor: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text(entry.content)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !entry.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(entry.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundColor(Color(hex: collectionColor))
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}
