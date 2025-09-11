//
//  PhotosView.swift
//  Squirrel2
//
//  Grid view for displaying photo entries
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PhotosView: View {
    @StateObject private var viewModel = PhotosViewModel()
    @EnvironmentObject var firebaseManager: FirebaseManager
    @State private var selectedPhoto: Entry?
    @State private var showingPhotoDetail = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Loading photos...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.photoEntries.isEmpty {
                    emptyStateView
                } else {
                    photoGrid
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingPhotoDetail) {
                if let photo = selectedPhoto {
                    PhotoDetailView(entry: photo, viewModel: viewModel)
                }
            }
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
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Photos Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Photos you capture will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.photoEntries) { entry in
                    PhotoThumbnailView(entry: entry, viewModel: viewModel)
                        .onTapGesture {
                            selectedPhoto = entry
                            showingPhotoDetail = true
                        }
                }
            }
            .padding(2)
        }
    }
}

struct PhotoThumbnailView: View {
    let entry: Entry
    let viewModel: PhotosViewModel
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                } else {
                    ProgressView()
                        .frame(width: geometry.size.width, height: geometry.size.width)
                }
                
                // Date overlay
                VStack {
                    Spacer()
                    HStack {
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(4)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        if let imageData = viewModel.getImageData(for: entry) {
            self.image = UIImage(data: imageData)
        }
    }
}

struct PhotoDetailView: View {
    let entry: Entry
    let viewModel: PhotosViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @StateObject private var collectionsViewModel = CollectionsViewModel()
    @State private var collectionNames: [String] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Photo
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(ProgressView())
                            .cornerRadius(12)
                    }
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 16) {
                        // Collections
                        if !collectionNames.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Collections")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    ForEach(collectionNames, id: \.self) { name in
                                        Text(name)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.squirrelPrimary.opacity(0.1))
                                            .foregroundColor(.squirrelPrimary)
                                            .cornerRadius(15)
                                    }
                                }
                            }
                        }
                        
                        // Description
                        if !entry.content.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text(entry.content)
                                    .font(.body)
                            }
                        }
                        
                        // Date & Time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Captured")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(entry.createdAt.formatted(date: .long, time: .shortened))
                                .font(.body)
                        }
                        
                        // Tags
                        if !entry.tags.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Tags")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    ForEach(entry.tags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Photo Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadImage()
            loadCollections()
        }
    }
    
    private func loadImage() {
        if let imageData = viewModel.getImageData(for: entry) {
            self.image = UIImage(data: imageData)
        }
    }
    
    private func loadCollections() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Start listening to collections
        collectionsViewModel.startListening(userId: userId)
        
        // Query CollectionEntry records to find which collections contain this entry
        let db = Firestore.firestore()
        db.collection("collection_entries")
            .whereField("entryId", isEqualTo: entry.id)
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching collection entries: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let collectionIds = documents.compactMap { doc in
                    doc.data()["collectionId"] as? String
                }
                
                // Map collection IDs to names
                DispatchQueue.main.async {
                    self.collectionNames = collectionIds.compactMap { collectionId in
                        self.collectionsViewModel.collections.first { $0.id == collectionId }?.name
                    }
                }
            }
    }
}
