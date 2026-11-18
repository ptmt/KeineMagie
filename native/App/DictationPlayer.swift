import AVFoundation
import Observation
import KeineMagieCore

@MainActor @Observable final class DictationPlayer: NSObject, AVAudioPlayerDelegate {
    var playing = false
    var rate: Float = 1 {didSet {player?.rate=rate}}
    var finished: ((Bool) -> Void)?
    var position: Double {playing ? (player?.currentTime ?? lastPosition) : lastPosition}
    var duration: Double? {player?.duration ?? lastDuration}
    private var lastPosition: Double = 0
    private var lastDuration: Double?
    private var player: AVAudioPlayer?
    private var generation = 0
    func play(_ data: Data, offset: Double = 0) throws {
        stop()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        let next = try AVAudioPlayer(data: data)
        next.enableRate = true; next.rate = rate; next.delegate = self
        next.currentTime=min(max(0,offset),max(0,next.duration-0.01))
        guard next.prepareToPlay(), next.play() else { throw APIError.invalidResponse }
        player = next; lastPosition=next.currentTime; lastDuration=next.duration; playing = true
    }
    func stop(resetTiming: Bool = false) {
        if playing {lastPosition=player?.currentTime ?? lastPosition}
        if resetTiming {lastPosition=0;lastDuration=nil}
        generation += 1; finished = nil; player?.stop(); player = nil; playing = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let completedPlayer = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == completedPlayer else { return }
            self.lastPosition = flag ? current.duration : current.currentTime
            self.playing = false
            self.finished?(flag)
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let failedPlayer=ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self,let current=self.player,ObjectIdentifier(current)==failedPlayer else {return}
            self.lastPosition=current.currentTime;self.playing=false;self.finished?(false)
        }
    }
}
