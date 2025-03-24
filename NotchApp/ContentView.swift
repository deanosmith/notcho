import SwiftUI
import AppKit

// Media command enum
enum MediaCommand: Int32 {
    case play = 0
    case pause = 1
    case nextTrack = 4
    case previousTrack = 5
    case changePlaybackPosition = 10 // For seeking
}

struct ContentView: View {
    @State private var isPlaying = false
    @State private var trackName = "Nothing Playing"
    @State private var artistName = ""
    @State private var thumbnail: NSImage? = nil
    @State private var currentMusicApp: String? = nil
    @State private var timer: Timer? = nil
    @State private var useSeekMode = UserDefaults.standard.bool(forKey: "useSeekMode") ?? false
    
    private let nowPlayingManager = NowPlayingManager()
    
    // Dynamic width based on Seek Mode
    private var notchWidth: CGFloat {
        useSeekMode ? 365 : 295 // Wider when Seek Mode is on, narrower when off
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(1))
                    .frame(width: 30, height: 30)
            }
            
            Spacer()
            
            // Playback controls (always show play/pause, show rewind/skip if in Seek Mode)
            HStack(spacing: 12) {
                if useSeekMode {
                    Button(action: previousOrRewind) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(currentMusicApp == nil)
                }
                
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(currentMusicApp == nil)
                
                if useSeekMode {
                    Button(action: nextOrFastForward) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(currentMusicApp == nil)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: notchWidth) // Dynamic width
        .background(Color.black.opacity(1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            useSeekMode.toggle()
            UserDefaults.standard.set(useSeekMode, forKey: "useSeekMode")
        }
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
                
                // Update playback state
                let playbackRate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0
                self.isPlaying = playbackRate > 0.0
                
                // Update track and artist info (still needed for internal state)
                if let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty {
                    // Only update thumbnail if the track has changed
                    let trackChanged = self.trackName != title
                    
                    self.trackName = title
                    self.artistName = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "Unknown Artist"
                    self.currentMusicApp = bundleID ?? "Unknown App"
                    
                    // Update artwork only if track changed and artwork data is available
                    if trackChanged, let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                        self.thumbnail = NSImage(data: artworkData)
                    }
                } else {
                    self.resetToIdleState()
                }
            }
        }
    }
    
    // Reset UI to idle state
    func resetToIdleState() {
        self.isPlaying = false
        self.trackName = "Nothing Playing"
        self.artistName = ""
        self.thumbnail = nil
        self.currentMusicApp = nil
    }
    
    // Toggle playback (play/pause)
    func togglePlayback() {
        guard currentMusicApp != nil else { return }
        
        nowPlayingManager.sendMediaCommand(command: isPlaying ? .pause : .play) { success in
            if !success {
                print("Failed to toggle playback for \(self.currentMusicApp ?? "unknown app")")
            }
        }
    }
    
    // Previous or Rewind (only used in Seek Mode)
    func previousOrRewind() {
        guard let currentMusicApp = currentMusicApp else { return }
        
        // Rewind: 15 seconds for Spotify, 5 seconds for Chrome
        let seconds = currentMusicApp == "com.spotify.client" ? -15.0 : -5.0
        if currentMusicApp.contains("com.google.Chrome") {
            // Use AppleScript for Chrome
            nowPlayingManager.seekInChrome(seconds: seconds) { success in
                if !success {
                    print("Failed to rewind in Chrome")
                }
            }
        } else {
            // Use MediaRemote for Spotify
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
        
        // Fast-forward: 15 seconds for Spotify, 5 seconds for Chrome
        let seconds = currentMusicApp == "com.spotify.client" ? 15.0 : 5.0
        if currentMusicApp.contains("com.google.Chrome") {
            // Use AppleScript for Chrome
            nowPlayingManager.seekInChrome(seconds: seconds) { success in
                if !success {
                    print("Failed to fast-forward in Chrome")
                }
            }
        } else {
            // Use MediaRemote for Spotify
            nowPlayingManager.seekBy(seconds: seconds) { success in
                if !success {
                    print("Failed to fast-forward for \(currentMusicApp)")
                }
            }
        }
    }
}

// MediaRemote Manager for system-wide Now Playing info and control
class NowPlayingManager {
    // Function types for MediaRemote
    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRNowPlayingClientGetBundleIdentifierFunction = @convention(c) (AnyObject) -> String?
    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (Int32, Any?) -> Bool
    private typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void
    
    // Load framework and function pointers once
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
    
    private lazy var sendCommand: MRMediaRemoteSendCommandFunction? = {
        guard let pointer = CFBundleGetFunctionPointerForName(mediaRemoteBundle, "MRMediaRemoteSendCommand" as CFString) else { return nil }
        return unsafeBitCast(pointer, to: MRMediaRemoteSendCommandFunction.self)
    }()
    
    private lazy var setElapsedTime: MRMediaRemoteSetElapsedTimeFunction? = {
        guard let pointer = CFBundleGetFunctionPointerForName(mediaRemoteBundle, "MRMediaRemoteSetElapsedTime" as CFString) else { return nil }
        return unsafeBitCast(pointer, to: MRMediaRemoteSetElapsedTimeFunction.self)
    }()
    
    // Fetch Now Playing info
    public func fetchNowPlayingInfo(completion: @escaping ([String: Any]?, String?) -> Void) {
        guard let getNowPlayingInfo = getNowPlayingInfo else {
            print("Failed to load MRMediaRemoteGetNowPlayingInfo")
            completion(nil, nil)
            return
        }
        
        guard let getBundleIdentifier = getBundleIdentifier else {
            print("Failed to load MRNowPlayingClientGetBundleIdentifier")
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
                // Log MediaRemote metadata
                print("MediaRemote Metadata: \(info)")
                print("Bundle ID: \(bundleID ?? "unknown")")
                completion(info, bundleID)
            } else {
                completion(info, nil)
            }
        }
    }
    
    // Send media control command
    public func sendMediaCommand(command: MediaCommand, completion: @escaping (Bool) -> Void) {
        guard let sendCommand = sendCommand else {
            print("Failed to load MRMediaRemoteSendCommand")
            completion(false)
            return
        }
        
        let success = sendCommand(command.rawValue, nil)
        completion(success)
    }
    
    // Seek by a relative number of seconds (for Spotify)
    public func seekBy(seconds: Double, completion: @escaping (Bool) -> Void) {
        fetchNowPlayingInfo { info, _ in
            guard let info = info,
                  let elapsedTime = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double,
                  let setElapsedTime = self.setElapsedTime else {
                print("Failed to fetch current playback position or load MRMediaRemoteSetElapsedTime")
                completion(false)
                return
            }
            
            let newTime = max(0, elapsedTime + seconds)
            setElapsedTime(newTime)
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
