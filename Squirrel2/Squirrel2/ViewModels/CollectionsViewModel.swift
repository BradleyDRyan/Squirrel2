//
//  CollectionsViewModel.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class CollectionsViewModel: ObservableObject {
    @Published var collections: [Collection] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private var collectionsListener: ListenerRegistration?
    private let db = Firestore.firestore()
    
    func startListening(userId: String) {
        print("[CollectionsViewModel] Starting collections listener for user: \(userId)")
        
        // Remove any existing listener
        stopListening()
        
        // Set up real-time listener for collections
        collectionsListener = db.collection("collections")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[CollectionsViewModel] Error listening to collections: \(error)")
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("[CollectionsViewModel] No documents in snapshot")
                    Task { @MainActor in
                        self.collections = []
                        self.isLoading = false
                    }
                    return
                }
                
                print("[CollectionsViewModel] Received \(documents.count) collections from snapshot")
                
                let newCollections = documents.compactMap { document -> Collection? in
                    let data = document.data()
                    
                    // Parse the collection data
                    guard let name = data["name"] as? String,
                          let userId = data["userId"] as? String else {
                        print("[CollectionsViewModel] Missing required fields in document: \(document.documentID)")
                        return nil
                    }
                    
                    // Parse rules if present
                    var rules: CollectionRules? = nil
                    if let rulesData = data["rules"] as? [String: Any] {
                        rules = CollectionRules(
                            keywords: rulesData["keywords"] as? [String] ?? [],
                            patterns: rulesData["patterns"] as? [String] ?? [],
                            examples: rulesData["examples"] as? [[String: String]] ?? [],
                            description: rulesData["description"] as? String ?? ""
                        )
                    }
                    
                    // Parse template if present
                    var template: CollectionTemplate? = nil
                    if let templateData = data["template"] as? [String: Any] {
                        template = CollectionTemplate(
                            fields: templateData["fields"] as? [String] ?? [],
                            prompts: templateData["prompts"] as? [String] ?? []
                        )
                    }
                    
                    // Parse settings if present
                    var settings: CollectionSettings? = nil
                    if let settingsData = data["settings"] as? [String: Any] {
                        settings = CollectionSettings(
                            isPublic: settingsData["isPublic"] as? Bool ?? false,
                            allowComments: settingsData["allowComments"] as? Bool ?? false,
                            defaultTags: settingsData["defaultTags"] as? [String] ?? []
                        )
                    }
                    
                    // Parse stats
                    let statsData = data["stats"] as? [String: Any]
                    let stats = CollectionStats(
                        entryCount: statsData?["entryCount"] as? Int ?? 0,
                        lastEntryAt: (statsData?["lastEntryAt"] as? Timestamp)?.dateValue()
                    )
                    
                    return Collection(
                        id: document.documentID,
                        userId: userId,
                        name: name,
                        description: data["description"] as? String ?? "",
                        icon: data["icon"] as? String ?? "📁",
                        color: data["color"] as? String ?? "#007AFF",
                        rules: rules,
                        template: template,
                        settings: settings,
                        stats: stats,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                        metadata: data["metadata"] as? [String: String]
                    )
                }
                
                Task { @MainActor in
                    self.collections = newCollections
                    self.isLoading = false
                    self.errorMessage = nil
                    print("[CollectionsViewModel] Updated collections list with \(self.collections.count) items")
                }
            }
    }
    
    func stopListening() {
        collectionsListener?.remove()
        collectionsListener = nil
    }
    
    deinit {
        stopListening()
    }
}