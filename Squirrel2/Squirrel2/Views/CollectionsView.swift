//
//  CollectionsView.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth
import Foundation

struct CollectionsView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @State private var collections: [Collection] = []
    @State private var isLoading = true
    @State private var selectedCollection: Collection?
    @State private var refreshTimer: Timer?
    
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
            // Set up periodic refresh
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                loadCollections()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    private func loadCollections() {
        guard let user = Auth.auth().currentUser else {
            print("[CollectionsView] No authenticated user")
            isLoading = false
            return
        }
        
        Task {
            do {
                print("[CollectionsView] Fetching collections for user: \(user.uid)")
                
                // Get auth token
                let token = try await user.getIDToken()
                
                // Make API request
                guard let url = URL(string: "\(AppConfig.apiBaseURL)/collections") else {
                    print("[CollectionsView] Invalid URL")
                    isLoading = false
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("[CollectionsView] Response status: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode != 200 {
                        if let errorString = String(data: data, encoding: .utf8) {
                            print("[CollectionsView] Error response: \(errorString)")
                        }
                        isLoading = false
                        return
                    }
                }
                
                // Debug: Print raw response
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[CollectionsView] Raw response: \(jsonString)")
                }
                
                let decoder = JSONDecoder()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                decoder.dateDecodingStrategy = .formatted(formatter)
                let collectionsResponse = try decoder.decode([Collection].self, from: data)
                print("[CollectionsView] Decoded \(collectionsResponse.count) collections")
                
                await MainActor.run {
                    self.collections = collectionsResponse
                    self.isLoading = false
                }
            } catch {
                print("[CollectionsView] Error loading collections: \(error)")
                print("[CollectionsView] Error details: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
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

// Color(hex:) extension is defined in DesignSystem/Colors.swift