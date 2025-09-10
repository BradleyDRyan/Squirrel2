//
//  CollectionDetailView.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth

struct CollectionDetailView: View {
    let collection: Collection
    @State private var entries: [Entry] = []
    @State private var isLoading = true
    @State private var refreshTimer: Timer?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Collection Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(collection.icon)
                            .font(.system(size: 48))
                        
                        Spacer()
                        
                        Text("\(entries.count) entries")
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
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if entries.isEmpty {
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
                        ForEach(entries) { entry in
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
            loadEntries()
            // Set up periodic refresh
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                loadEntries()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    private func loadEntries() {
        guard let user = Auth.auth().currentUser else {
            print("[CollectionDetailView] No authenticated user")
            isLoading = false
            return
        }
        
        Task {
            do {
                print("[CollectionDetailView] Fetching entries for collection: \(collection.id)")
                
                // Get auth token
                let token = try await user.getIDToken()
                
                // Make API request
                guard let url = URL(string: "\(AppConfig.apiBaseURL)/collections/\(collection.id)/entries") else {
                    print("[CollectionDetailView] Invalid URL")
                    isLoading = false
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("[CollectionDetailView] Response status: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode != 200 {
                        if let errorString = String(data: data, encoding: .utf8) {
                            print("[CollectionDetailView] Error response: \(errorString)")
                        }
                        isLoading = false
                        return
                    }
                }
                
                // Debug: Print raw response
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[CollectionDetailView] Raw response: \(jsonString)")
                }
                
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let entriesResponse = try decoder.decode([Entry].self, from: data)
                print("[CollectionDetailView] Decoded \(entriesResponse.count) entries")
                
                await MainActor.run {
                    self.entries = entriesResponse.sorted { $0.createdAt > $1.createdAt }
                    self.isLoading = false
                }
            } catch {
                print("[CollectionDetailView] Error loading entries: \(error)")
                print("[CollectionDetailView] Error details: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
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