//
//  CollectionsView.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CollectionsView: View {
    @State private var collections: [Collection] = []
    @State private var isLoading = true
    @State private var selectedCollection: Collection?
    @State private var listener: ListenerRegistration?
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                } else if collections.isEmpty {
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
                        ForEach(collections) { collection in
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
            loadCollections()
        }
        .onDisappear {
            listener?.remove()
        }
    }
    
    private func loadCollections() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        listener?.remove()
        
        listener = db.collection("collections")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error loading collections: \(error)")
                    isLoading = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    isLoading = false
                    return
                }
                
                self.collections = documents.compactMap { doc in
                    try? doc.data(as: Collection.self)
                }.sorted { collection1, collection2 in
                    collection1.createdAt > collection2.createdAt
                }
                
                isLoading = false
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
            
            if !collection.description.isEmpty {
                Text(collection.description)
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

// Helper extension for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}