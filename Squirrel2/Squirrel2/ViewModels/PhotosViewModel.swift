//
//  PhotosViewModel.swift
//  Squirrel2
//
//  ViewModel for managing photo entries
//

import SwiftUI
import FirebaseFirestore
import Combine

@MainActor
class PhotosViewModel: ObservableObject {
    @Published var photoEntries: [Entry] = []
    @Published var isLoading = true
    @Published var error: String?
    
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    
    func startListening(userId: String) {
        isLoading = true
        error = nil
        
        listener = db.collection("entries")
            .whereField("userId", isEqualTo: userId)
            .whereField("type", isEqualTo: "photo")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.error = error.localizedDescription
                    self.isLoading = false
                    print("Error fetching photos: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.photoEntries = []
                    self.isLoading = false
                    return
                }
                
                self.photoEntries = documents.compactMap { doc in
                    do {
                        var entry = try doc.data(as: Entry.self)
                        
                        // Ensure we have the document ID
                        if entry.id.isEmpty {
                            entry = Entry(
                                id: doc.documentID,
                                userId: entry.userId,
                                spaceIds: entry.spaceIds,
                                conversationId: entry.conversationId,
                                title: entry.title,
                                content: entry.content,
                                type: entry.type,
                                mood: entry.mood,
                                tags: entry.tags,
                                attachments: entry.attachments,
                                location: entry.location,
                                weather: entry.weather,
                                imageUrl: entry.imageUrl,
                                createdAt: entry.createdAt,
                                updatedAt: entry.updatedAt,
                                metadata: entry.metadata
                            )
                        }
                        
                        return entry
                    } catch {
                        print("Error decoding photo entry: \(error)")
                        return nil
                    }
                }
                
                self.isLoading = false
                print("Loaded \(self.photoEntries.count) photos")
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    func getImageURL(for entry: Entry) -> String? {
        // Get Firebase Storage URL from imageUrl field
        return entry.imageUrl
    }
    
    func getImageData(for entry: Entry) -> Data? {
        // For backward compatibility with base64 stored images
        if let imageDataString = entry.metadata?["imageData"],
           imageDataString.contains("base64,") {
            // Remove the data URL prefix to get just the base64 string
            let base64String = imageDataString
                .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
                .replacingOccurrences(of: "data:image/png;base64,", with: "")
            
            return Data(base64Encoded: base64String)
        }
        
        // For new images, they'll be loaded via URL
        return nil
    }
    
    deinit {
        listener?.remove()
    }
}
