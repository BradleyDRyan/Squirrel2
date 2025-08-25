import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "leaf.fill")
                    .imageScale(.large)
                    .foregroundColor(.green)
                    .font(.system(size: 60))
                    .padding()
                
                Text("Squirrel 2.0")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Connected to Firebase")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                
                Spacer()
                
                VStack(spacing: 20) {
                    NavigationLink(destination: DashboardView()) {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
}

struct DashboardView: View {
    var body: some View {
        VStack {
            Text("Dashboard")
                .font(.largeTitle)
                .padding()
            
            Spacer()
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Account") {
                Text("User Profile")
                Text("Notifications")
            }
            
            Section("About") {
                Text("Version 2.0")
                Text("Privacy Policy")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}