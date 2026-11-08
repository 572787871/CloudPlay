import XCTest
import AVFoundation
import UIKit
import MobileVLCKit
@testable import CloudPlay

@MainActor final class PlaybackEngineTests: XCTestCase {
    private func fixture(_ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for:Self.self).url(forResource:"generated",withExtension:ext))
    }
    func testGeneratedMP4ActuallyPlaysAndSeeksWithAVPlayer() async throws {
        let item=AVPlayerItem(url:try fixture("mp4"))
        let player=AVPlayer(playerItem:item)
        let ready=keyValueObservingExpectation(for:item,keyPath:"status",expectedValue:AVPlayerItem.Status.readyToPlay.rawValue)
        await fulfillment(of:[ready],timeout:20)
        XCTAssertEqual(item.status,.readyToPlay)
        let progress=expectation(description:"AVPlayer passes real 0.5 second media time")
        let token=player.addBoundaryTimeObserver(forTimes:[NSValue(time:CMTime(seconds:0.5,preferredTimescale:600))],queue:.main) {progress.fulfill()}
        defer {player.pause();player.removeTimeObserver(token)}
        player.play()
        await fulfillment(of:[progress],timeout:15)
        let seek=expectation(description:"AVPlayer completes actual seek")
        player.seek(to:CMTime(seconds:4,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) { finished in
            XCTAssertTrue(finished);seek.fulfill()
        }
        await fulfillment(of:[seek],timeout:10)
        XCTAssertEqual(player.currentTime().seconds,4,accuracy:0.5)
    }
    func testGeneratedMKVActuallyPlaysAndSeeksWithVLC() async throws {
        let player=VLCMediaPlayer()
        let canvas=UIView(frame:CGRect(x:0,y:0,width:320,height:180))
        let probe=VLCProbe();probe.player=player
        let progress=expectation(description:"VLC passes real 0.5 second MKV media time")
        probe.target=0.5;probe.onTarget={progress.fulfill()}
        player.delegate=probe;player.drawable=canvas;player.media=VLCMedia(url:try fixture("mkv"))
        defer {player.stop();player.drawable=nil;player.delegate=nil}
        player.play()
        await fulfillment(of:[progress],timeout:20)
        XCTAssertTrue(player.isSeekable)
        XCTAssertGreaterThan(Double(player.media?.length.intValue ?? 0),7000)
        let seek=expectation(description:"VLC reports media time after actual seek")
        probe.target=4.5;probe.onTarget={seek.fulfill()};player.time=VLCTime(int:5000)
        await fulfillment(of:[seek],timeout:10)
        XCTAssertGreaterThanOrEqual(player.time.intValue,4500)
    }
}

@MainActor private final class VLCProbe: NSObject,VLCMediaPlayerDelegate {
    var player: VLCMediaPlayer?
    var target: Double=0
    var onTarget: (()->Void)?
    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, let player=self.player, Double(player.time.intValue)/1000 >= self.target else {return}
            let callback=self.onTarget;self.onTarget=nil;callback?()
        }
    }
}
