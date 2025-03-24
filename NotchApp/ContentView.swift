import SwiftUI
import AppKit

struct ContentView: View {
    @State private var isPlaying = false
    @State private var trackName = "Nothing Playing"
    @State private var artistName = ""
    @State private var thumbnail: NSImage? = nil
    @State private var currentMusicApp: String? = nil
    @State private var timer: Timer? = nil
    
    private let nowPlayingManager = NowPlayingManager()
    
    var body: some View {
        HStack(spacing: 10) {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30) // Adjusted from 3x3 for visibility
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
                
                // Update track and artist info
                if let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty {
                    self.trackName = title
                    self.artistName = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "Unknown Artist"
                    self.currentMusicApp = bundleID ?? "Unknown App"
                    
                    // Update artwork if available
                    if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                        self.thumbnail = NSImage(data: artworkData)
                    } else {
                        self.thumbnail = nil
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
    
    // Placeholder playback controls (to be implemented later)
    func togglePlayback() {
        guard currentMusicApp != nil else { return }
        // TODO: Implement system-wide playback control
        print("Toggle playback not yet implemented for app: \(currentMusicApp ?? "nil")")
    }
    
    func previousTrack() {
        guard currentMusicApp != nil else { return }
        // TODO: Implement system-wide previous track
        print("Previous track not yet implemented for app: \(currentMusicApp ?? "nil")")
    }
    
    func nextTrack() {
        guard currentMusicApp != nil else { return }
        // TODO: Implement system-wide next track
        print("Next track not yet implemented for app: \(currentMusicApp ?? "nil")")
    }
}

// MediaRemote Manager for system-wide Now Playing info
class NowPlayingManager {
    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRNowPlayingClientGetBundleIdentifierFunction = @convention(c) (AnyObject) -> String?
    
    func fetchNowPlayingInfo(completion: @escaping ([String: Any]?, String?) -> Void) {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL),
              let getNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
              let getBundleIdentifierPointer = CFBundleGetFunctionPointerForName(bundle, "MRNowPlayingClientGetBundleIdentifier" as CFString) else {
            print("Failed to load MediaRemote framework")
            completion(nil, nil)
            return
        }
        
        let getNowPlayingInfo = unsafeBitCast(getNowPlayingInfoPointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        let getBundleIdentifier = unsafeBitCast(getBundleIdentifierPointer, to: MRNowPlayingClientGetBundleIdentifierFunction.self)
        
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
}

// Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
