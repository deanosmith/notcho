import SwiftUI
import AppKit

struct ContentView: View {
    @State private var isPlaying = false
    @State private var trackName = "Nothing Playing"
    @State private var artistName = ""
    @State private var thumbnail: NSImage? = nil
    @State private var currentMusicApp: String? = nil
    @State private var timer: Timer? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 3, height: 3)
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(1))
                    .frame(width: 30, height: 30)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(trackName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text(artistName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: previousTrack) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(currentMusicApp == nil)
                
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(currentMusicApp == nil)
                
                Button(action: nextTrack) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(currentMusicApp == nil)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Color.black.opacity(1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            setupNotificationObservers()
            startPollingForMusicInfo()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    func setupNotificationObservers() {
        let nc = DistributedNotificationCenter.default()
        nc.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { notification in
            self.handleSpotifyNotification(notification)
        }
    }
    
    func startPollingForMusicInfo() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.checkSpotifyStatus()
        }
    }
    
    func checkSpotifyStatus() {
        let appleScript = """
        tell application "System Events"
            set spotifyRunning to (name of processes) contains "Spotify"
        end tell
        
        if spotifyRunning then
            tell application "Spotify"
                set isPlaying to player state is playing
                if isPlaying then
                    set trackName to name of current track
                    set artistName to artist of current track
                    return {trackName:trackName, artistName:artistName, isPlaying:isPlaying}
                else
                    return {trackName:"", artistName:"", isPlaying:false}
                end if
            end tell
        else
            return {trackName:"", artistName:"", isPlaying:false}
        end if
        """
        
        let script = NSAppleScript(source: appleScript)
        var errorInfo: NSDictionary? = nil
        
        if let script = script {
            let result = script.executeAndReturnError(&errorInfo)
            
            if errorInfo == nil {
                if let trackNameDesc = result.value(forKey: "trackName") as? NSAppleEventDescriptor {
                    let trackNameStr = trackNameDesc.stringValue ?? ""
                    if !trackNameStr.isEmpty {
                        self.trackName = trackNameStr
                        self.artistName = (result.value(forKey: "artistName") as? NSAppleEventDescriptor)?.stringValue ?? "Unknown Artist"
                        self.isPlaying = (result.value(forKey: "isPlaying") as? NSAppleEventDescriptor)?.booleanValue ?? false
                        self.currentMusicApp = self.isPlaying ? "Spotify" : nil
                    } else {
                        self.currentMusicApp = nil
                        self.trackName = "Nothing Playing"
                        self.artistName = ""
                        self.thumbnail = nil
                    }
                }
            } else {
                self.currentMusicApp = nil
                //print("AppleScript Error: \(errorInfo ?? "Unknown error")")
            }
        }
    }
    
    func handleMusicNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        currentMusicApp = "Music"
        
        if let playerState = userInfo["Player State"] as? String {
            isPlaying = playerState == "Playing"
        }
        
        trackName = userInfo["Name"] as? String ?? "Unknown Track"
        artistName = userInfo["Artist"] as? String ?? "Unknown Artist"
        
        if let artworkData = userInfo["Artwork"] as? Data {
            thumbnail = NSImage(data: artworkData)
        }
    }
    
    func handleSpotifyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        currentMusicApp = "Spotify"
        
        if let playerState = userInfo["Player State"] as? String {
            isPlaying = playerState == "Playing"
        }
        
        trackName = userInfo["Name"] as? String ?? "Unknown Track"
        artistName = userInfo["Artist"] as? String ?? "Unknown Artist"
        
        if let artworkURLString = userInfo["Artwork URL"] as? String,
           let url = URL(string: artworkURLString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let image = NSImage(data: data) {
                    DispatchQueue.main.async {
                        self.thumbnail = image
                    }
                }
            }.resume()
        }
    }
    
    func togglePlayback() {
        guard let appName = currentMusicApp, appName == "Spotify" else {
            print("Spotify not detected")
            return
        }
        
        let scriptSource = """
        tell application "Spotify"
            playpause
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary? = nil
            script.executeAndReturnError(&errorInfo)
            
            if let error = errorInfo {
                print("Toggle Playback Error: \(error)")
                self.currentMusicApp = nil
                self.isPlaying = false
                self.trackName = "Nothing Playing"
                self.artistName = ""
                self.thumbnail = nil
            } else {
                self.isPlaying.toggle()
            }
        }
    }
    
    func previousTrack() {
        guard let appName = currentMusicApp, appName == "Spotify" else {
            print("Spotify not detected")
            return
        }
        
        let scriptSource = """
        tell application "Spotify"
            previous track
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary? = nil
            script.executeAndReturnError(&errorInfo)
            if let error = errorInfo {
                print("Previous Track Error: \(error)")
            }
        }
    }
    
    func nextTrack() {
        guard let appName = currentMusicApp, appName == "Spotify" else {
            print("Spotify not detected")
            return
        }
        
        let scriptSource = """
        tell application "Spotify"
            next track
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary? = nil
            script.executeAndReturnError(&errorInfo)
            if let error = errorInfo {
                print("Next Track Error: \(error)")
            }
        }
    }
    
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
}
