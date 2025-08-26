import AVFoundation
import AudioToolbox
import UIKit

class SoundManager {
    static let shared = SoundManager()
    
    private init() {}
    
    // Play a system sound for task completion
    func playSuccessChime() {
        // Ensure audio session allows mixing with other audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
        // Popular system sound IDs to try:
        // 1052 - Ping (sharp, clear)
        // 1054 - Keyboard tap (subtle click)
        // 1057 - Tink (subtle metal tap)
        // 1103 - Beep beep (attention-getting)
        // 1104 - Tock (wood block)
        // 1105 - Beep (single)
        // 1256 - New mail (pleasant chime)
        // 1001 - Sent mail (whoosh)
        // 1004 - SMS received (ding-ding)
        // 1013 - Tweet sent
        // 1016 - Classic email sent
        // 1150 - Key press click
        // 1306 - Keyboard press delete
        // 1315 - Lock sound (click)
        // 1336 - Payment success
        AudioServicesPlaySystemSound(1001)
        
        // Optional: Add haptic feedback for iPhone
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    // Alternative chime sounds
    func playAlternativeChime(_ soundID: SystemSoundID) {
        AudioServicesPlaySystemSound(soundID)
    }
    
    // Common system sounds
    enum SystemChime: SystemSoundID {
        case tink = 1057
        case beep = 1103
        case tap = 1104
        case newMail = 1000
        case sentMail = 1001
        
        func play() {
            AudioServicesPlaySystemSound(self.rawValue)
        }
    }
}
