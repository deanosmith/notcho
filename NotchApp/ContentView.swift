import SwiftUI
import AppKit

// Media command enum (simplified, no play/pause needed)
enum MediaCommand: Int32 {
    case changePlaybackPosition = 10 // For seeking only
}

struct ContentView: View {
    @State private var trackName = "Nothing Playing"
    @State private var artistName = ""
    @State private var thumbnail: NSImage? = nil
    @State private var currentMusicApp: String? = nil
    @State private var timer: Timer? = nil
    @State private var useSeekMode = UserDefaults.standard.bool(forKey: "useSeekMode")
    
    private let nowPlayingManager = NowPlayingManager()
    
    // Dynamic width based on Seek Mode
    private var notchWidth: CGFloat {
        useSeekMode ? 360 : 303 // On, Off
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Thumbnail
                if let thumbnail = thumbnail {
                    Button(action: openCurrentMediaSource) {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                ZStack {
                    Color.clear
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                
                // Playback controls (only rewind/skip when in Seek Mode)
                HStack(spacing: 6) {
                    if useSeekMode {
                        Button(action: previousOrRewind) {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(currentMusicApp == nil)
                    }
                    
                    // Waveform button to toggle seek mode
                    Button(action: toggleSeekMode) {
                        Image(systemName: "waveform")
                            .font(.system(size: 24))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Toggle Seek Mode")
                    
                    if useSeekMode {
                        Button(action: nextOrFastForward) {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(currentMusicApp == nil)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 40, alignment: .top) // Set minimum height and align to top
        .frame(width: notchWidth) // Dynamic width
        .background(Color.black.opacity(0))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onAppear {
            startPollingForMusicInfo()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // Start polling system-wide media info
    func startPollingForMusicInfo() {
        updateNowPlayingInfo() // Initial fetch
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateNowPlayingInfo()
        }
    }
    
    // Fetch and update media info using MediaRemote
    func updateNowPlayingInfo() {
        nowPlayingManager.fetchNowPlayingInfo { info, bundleID in
            DispatchQueue.main.async {
                guard let info = info else {
                    self.resetToIdleState()
                    return
                }
                
                guard let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else {
                    self.resetToIdleState()
                    return
                }
                
                let trackChanged = self.trackName != title
                self.trackName = title
                self.artistName = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "Unknown Artist"
                
                // Heuristic detection if bundleID is unavailable
                var inferredApp: String? = nil
                if let mediaType = info["kMRMediaRemoteNowPlayingInfoMediaType"] as? String,
                   mediaType == "kMRMediaRemoteNowPlayingInfoTypeAudio",
                   info["kMRMediaRemoteNowPlayingInfoTrackNumber"] != nil {
                    inferredApp = "Spotify"
                } else if info["kMRMediaRemoteNowPlayingInfoCurrentPlaybackDate"] != nil,
                          (info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String)?.isEmpty ?? false,
                          info["kMRMediaRemoteNowPlayingInfoMediaType"] == nil {
                    inferredApp = "YouTube (Chrome)"
                }

                self.currentMusicApp = bundleID ?? inferredApp ?? "Unknown App"
                
                if self.currentMusicApp == "Unknown App" {
                    print("---- Now Playing Info Dump ----")
                    for (key, value) in info {
                        print("\(key): \(value)")
                    }
                    print("---- End Dump ----")
                }
                
                if trackChanged, let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                    self.thumbnail = NSImage(data: artworkData)
                }
            }
        }
    }
    
    // Reset UI to idle state
    func resetToIdleState() {
        self.trackName = "Nothing Playing"
        self.artistName = ""
        self.thumbnail = nil
        self.currentMusicApp = nil
    }
    
    // Toggle seek mode
    func toggleSeekMode() {
        useSeekMode.toggle()
        UserDefaults.standard.set(useSeekMode, forKey: "useSeekMode")
    }
    
    // Previous or Rewind (only used in Seek Mode)
    func previousOrRewind() {
        guard let currentMusicApp = currentMusicApp else { return }
        
        let seconds = currentMusicApp == "com.spotify.client" ? -15.0 : -10.0
        if currentMusicApp.contains("com.google.Chrome") {
            nowPlayingManager.seekInChrome(seconds: seconds) { success in
                if !success {
                    print("Failed to rewind in Chrome")
                }
            }
        } else {
            nowPlayingManager.seekBy(seconds: seconds) { success in
                if !success {
                    print("Failed to rewind for \(currentMusicApp)")
                }
            }
        }
    }
    
    // Next or Fast-Forward (only used in Seek Mode)
    func nextOrFastForward() {
        guard let currentMusicApp = currentMusicApp else { return }
        
        let seconds = currentMusicApp == "com.spotify.client" ? 15.0 : 10.0
        if currentMusicApp.contains("com.google.Chrome") {
            nowPlayingManager.seekInChrome(seconds: seconds) { success in
                if !success {
                    print("Failed to fast-forward in Chrome")
                }
            }
        } else {
            nowPlayingManager.seekBy(seconds: seconds) { success in
                if !success {
                    print("Failed to fast-forward for \(currentMusicApp)")
                }
            }
        }
    }
    
    func openCurrentMediaSource() {
        guard let appName = currentMusicApp else { return }

        if appName == "Spotify" {
            NSWorkspace.shared.launchApplication("Spotify")
        } else if appName == "YouTube (Chrome)" {
            NSWorkspace.shared.launchApplication("Google Chrome")
        } else {
            print("No associated app for: \(appName)")
        }
    }
}

// MediaRemote Manager for system-wide Now Playing info and control
class NowPlayingManager {
    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRNowPlayingClientGetBundleIdentifierFunction = @convention(c) (AnyObject) -> String?
    private typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void
    
    private lazy var mediaRemoteBundle: CFBundle? = {
        CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL)
    }()
    
    private lazy var getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction? = {
        guard let pointer = CFBundleGetFunctionPointerForName(mediaRemoteBundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) else { return nil }
        return unsafeBitCast(pointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
    }()
    
    private lazy var getBundleIdentifier: MRNowPlayingClientGetBundleIdentifierFunction? = {
        guard let pointer = CFBundleGetFunctionPointerForName(mediaRemoteBundle, "MRNowPlayingClientGetBundleIdentifier" as CFString) else { return nil }
        return unsafeBitCast(pointer, to: MRNowPlayingClientGetBundleIdentifierFunction.self)
    }()
    
    private lazy var setElapsedTime: MRMediaRemoteSetElapsedTimeFunction? = {
        guard let pointer = CFBundleGetFunctionPointerForName(mediaRemoteBundle, "MRMediaRemoteSetElapsedTime" as CFString) else { return nil }
        return unsafeBitCast(pointer, to: MRMediaRemoteSetElapsedTimeFunction.self)
    }()
    
    // Fetch Now Playing info
    public func fetchNowPlayingInfo(completion: @escaping ([String: Any]?, String?) -> Void) {
        guard let getNowPlayingInfo = getNowPlayingInfo,
              let getBundleIdentifier = getBundleIdentifier else {
            print("Failed to load required MediaRemote functions")
            completion(nil, nil)
            return
        }
        
        getNowPlayingInfo(DispatchQueue.main) { info in
            if let clientData = info["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] as? Data,
               let clientClass = NSClassFromString("_MRNowPlayingClientProtobuf"),
               let clientObject = clientClass.alloc() as? NSObject,
               clientObject.responds(to: Selector(("initWithData:"))) {
                _ = clientObject.perform(Selector(("initWithData:")), with: clientData)
                let bundleID = getBundleIdentifier(clientObject)
                completion(info, bundleID)
            } else {
                completion(info, nil)
            }
        }
    }
    
    // Seek by a relative number of seconds (for Spotify)
    public func seekBy(seconds: Double, completion: @escaping (Bool) -> Void) {
        fetchNowPlayingInfo { info, _ in
            guard let elapsedTime = info?["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double,
                  let setElapsedTime = self.setElapsedTime else {
                print("Failed to fetch playback position or set elapsed time")
                completion(false)
                return
            }

            setElapsedTime(max(0, elapsedTime + seconds))
            completion(true)
        }
    }
    
    // Seek in Chrome using AppleScript
    public func seekInChrome(seconds: Double, completion: @escaping (Bool) -> Void) {
        let scriptSource = """
        tell application "Google Chrome"
            set windowList to every window
            repeat with aWindow in windowList
                set tabList to every tab of aWindow
                repeat with aTab in tabList
                    if (URL of aTab contains "youtube.com") then
                        tell aTab
                            execute javascript "var vid = document.querySelector('video'); if (vid) { vid.currentTime += \(seconds); }"
                        end tell
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary? = nil
            script.executeAndReturnError(&errorInfo)
            if let error = errorInfo {
                print("AppleScript Error for Chrome seek: \(error)")
                completion(false)
            } else {
                completion(true)
            }
        } else {
            completion(false)
        }
    }
}

// Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
