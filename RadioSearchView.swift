//
//  RadioSearchView.swift
//  2 Music 2 Furious - MILESTONE 7.3
//
//  Radio station search and favorites
//  Tap station to play immediately
//

import SwiftUI

struct RadioSearchView: View {
    @ObservedObject var radioAPI: RadioBrowserAPI
    @ObservedObject var musicPlayer: AudioPlayer
    let dismiss: () -> Void
    
    @State private var searchText = ""
    @State private var searchMode: SearchMode = .name
    @State private var showingFavorites = false
    
    enum SearchMode: String, CaseIterable {
        case name = "Name"
        case top100 = "Top 100"
        case genre = "Genre"
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if showingFavorites {
                    favoritesView
                } else {
                    searchView
                }
            }
            .navigationTitle("Radio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var searchView: some View {
        VStack {
            // Search mode picker
            Picker("Search Mode", selection: $searchMode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Search bar (Hidden for Top 100)
            if searchMode != .top100 {
                HStack {
                    TextField(searchPlaceholder, text: $searchText, onCommit: { performSearch() })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Search") { performSearch() }
                        .disabled(searchText.isEmpty)
                }
                .padding(.horizontal)
            } else {
                Text("Most popular stations globally")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }
            
            // Genre quick buttons
            if searchMode == .genre {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Pop", "Rock", "Jazz", "Classical", "Electronic", "Hip Hop", "Country"], id: \.self) { genre in
                            Button(genre) {
                                searchText = genre
                                performSearch()
                            }
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 4)
            }
            
            // Favorites section
            if radioAPI.favoriteStations.count > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                        Text("Favorites")
                            .font(.headline)
                        Spacer()
                        Button("View All") { showingFavorites = true }
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(radioAPI.favoriteStations.prefix(5)) { station in
                                Button(action: { playStation(station) }) {
                                    VStack(spacing: 4) {
                                        stationIcon(station, size: 60)
                                        Text(station.displayName)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(width: 70)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Results
            if radioAPI.isSearching {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else {
                List(radioAPI.searchResults) { station in
                    HStack {
                        stationIcon(station, size: 50)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.displayName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(station.displayCountry)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Popularity Badge
                        HStack(spacing: 4) {
                            Image(systemName: "headphones")
                                .font(.caption2)
                            Text(station.formattedClicks)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8)
                        
                        Button(action: { radioAPI.toggleFavorite(station) }) {
                            Image(systemName: radioAPI.isFavorite(station) ? "star.fill" : "star")
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { playStation(station) }
                }
            }
        }
        // Auto-search when switching to Top 100
        .onChange(of: searchMode) { mode in
            if mode == .top100 {
                performSearch()
            }
        }
    }
    
    private var favoritesView: some View {
        VStack {
            HStack {
                Button(action: { showingFavorites = false }) {
                    Label("Back", systemImage: "chevron.left")
                }
                Spacer()
            }
            .padding()
            
            if radioAPI.favoriteStations.isEmpty {
                Spacer()
                Text("No favorites yet")
                    .foregroundColor(.gray)
                Spacer()
            } else {
                List(radioAPI.favoriteStations) { station in
                    HStack {
                        stationIcon(station, size: 50)
                        
                        VStack(alignment: .leading) {
                            Text(station.displayName)
                                .font(.headline)
                            Text(station.displayCountry)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: { radioAPI.toggleFavorite(station) }) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { playStation(station) }
                }
            }
        }
    }
    
    @ViewBuilder
    private func stationIcon(_ station: RadioStation, size: CGFloat) -> some View {
        if !station.favicon.isEmpty, let url = URL(string: station.favicon) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                radioPlaceholder(size: size)
            }
            .frame(width: size, height: size)
            .cornerRadius(8)
        } else {
            radioPlaceholder(size: size)
        }
    }
    
    private func radioPlaceholder(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.orange.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.orange)
            )
    }
    
    private var searchPlaceholder: String {
        switch searchMode {
        case .name: return "Station name..."
        case .top100: return ""
        case .genre: return "Genre (e.g. jazz, rock)..."
        }
    }
    
    private func performSearch() {
        switch searchMode {
        case .name: radioAPI.searchByName(query: searchText)
        case .top100: radioAPI.fetchTopStations()
        case .genre: radioAPI.searchByTag(tag: searchText)
        }
    }
    
    private func playStation(_ station: RadioStation) {
        // Play immediately when tapped
        musicPlayer.addRadioStream(name: station.displayName, streamURL: station.url)
        dismiss()
    }
}
