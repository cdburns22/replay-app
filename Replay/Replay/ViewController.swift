//
//  ViewController.swift
//  Replay
//
//  Created by Rajiv Singh on 8/15/17.
//  Copyright © 2017 Rajiv Singh. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit

class ViewController: UIViewController, AVAssetResourceLoaderDelegate {
    
    let media = "https://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4"
    var player: AVPlayer? = nil
    
    @IBOutlet var statusLabel : UILabel? = nil
    
    lazy var spinner = UIActivityIndicatorView.init(activityIndicatorStyle: .whiteLarge)
    
    // MARK:
    // MARK: View life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        registerNotifications()
        initAudioSession()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        initPlayer()
    }
    
    // MARK:
    // MARK: memory management
    
    deinit {
        deregisterNotifications()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK:
    // MARK: Initializations
    
    func initAudioSession() -> Void {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
        }
        catch {
            print("Setting category to AVAudioSessionCategoryPlayback failed.")
        }
    }
    
    func initPlayer() -> Void {
        guard let url = URL(string: media) else {
            self.statusLabel?.text = "No media specified for playback"
            return
        }
        
        let playableKey = "playable"
        var asset = AVURLAsset.init(url: url, options: [AVURLAssetAllowsCellularAccessKey : false])
        
        if asset.isDownloaded() {
            // Asset was already downloaded before. So we recreate it from the local URL.
            if let localAssetURL = asset.downloadPath() {
                asset = AVURLAsset.init(url: localAssetURL)
            }
        }else {
            // Asset isn't downloaded yet. Set its resource loader so that we can export it later when its finished.
            asset.resourceLoader.setDelegate(self, queue: DispatchQueue.main)
        }
        
        asset.loadValuesAsynchronously(forKeys: [playableKey], completionHandler: {
            DispatchQueue.main.async {
                
                var error: NSError? = nil
                let status = asset.statusOfValue(forKey: playableKey, error: &error)
                switch status {
                case .loaded:
                    // Sucessfully loaded. Continue processing.
                    self.statusLabel?.text = "Player initialized"
                    self.startPlayer(forAsset: asset)
                    break
                case .failed:
                    // Handle error
                    self.statusLabel?.text = "Failed to initialize the player. Error: \(error?.localizedDescription ?? "")"
                    break
                case .cancelled:
                    // Terminate processing
                    self.statusLabel?.text = "Initializing player was cancelled. Error: \(error?.localizedDescription ?? "")"
                    break
                default:
                    // Handle all other cases
                    self.statusLabel?.text = "Unknown error while initilizing the player"
                    break
                }
            }
        })
    }
    
    // MARK:
    // MARK: Playback
    
    func startPlayer(forAsset asset: AVURLAsset?) -> Void {
        guard let mediaAsset = asset else {
            self.statusLabel?.text = "Media asset not present"
            return
        }
        
        let playerItem = AVPlayerItem.init(asset: mediaAsset)
        
        if let playerViewController = self.presentedViewController as? AVPlayerViewController {
            playerViewController.player?.replaceCurrentItem(with: playerItem)
            playerViewController.player?.restart()
        }else {
            // Create a new AVPlayerViewController and pass it a reference to the player.
            self.player = AVPlayer.init(playerItem: playerItem)
            self.player?.actionAtItemEnd = .none
            
            let controller = AVPlayerViewController()
            controller.player = self.player
            
            // Modally present the player and call the player's play() method when complete.
            self.present(controller, animated: true) {
                controller.player?.play()
            }
        }
    }
    
    // MARK:
    // MARK: AVPlayer notifications
    
    func registerNotifications() -> Void {
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd(notification:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    func deregisterNotifications() -> Void {
        NotificationCenter.default.removeObserver(self)
    }
    
    func playerItemDidReachEnd(notification: NSNotification) -> Void {
        
        guard notification.object as? AVPlayerItem  == self.player?.currentItem else {
            return
        }
        
        guard let asset = self.player?.currentItem?.asset as? AVURLAsset else {
            return
        }
        
        if asset.isDownloaded() {
            // Asset was already downloaded. We play it again.
            self.player?.restart()
            return
        }
        
        if asset.isExportable == false {
            self.player?.restart()
            return
        }
        
        let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        
        exporter?.outputURL = asset.downloadPath(create: true)
        exporter?.outputFileType = AVFileTypeQuickTimeMovie
        
        exporter?.exportAsynchronously(completionHandler: {
            DispatchQueue.main.async {
                if exporter?.status == .completed {
                    // Asset exported successfully. We configure the player with this downloaded  asset and play it again.
                    self.initPlayer()
                }else {
                    // Asset export failed. Restart the media.
                    self.player?.restart()
                }
            }
        })
    }
    
    // MARK:
    // MARK: Spinner
    
    func showSpinner(inView parentView: UIView) -> Void {
        spinner.center = parentView.center
        parentView.addSubview(spinner)
        spinner.startAnimating()
    }
    
    func hideSpinner() -> Void {
        spinner.stopAnimating()
        spinner.removeFromSuperview()
    }
}

// MARK:
// MARK: Extensions

extension AVPlayer {
    func restart() -> Void {
        self.pause()
        self.seek(to: kCMTimeZero)
        self.play()
    }
}

extension AVURLAsset {
    
    func isDownloaded() -> Bool {
        
        // First check if media is present at asset's URL. This could be the case if asset was created locally.
        let mediaExists = FileManager.init().fileExists(atPath: self.url.path)
        if mediaExists == false {
            // Media is not present at asset's URL. Derive the download path to check if its present there instead.
            if let downloadedAssetURL = self.downloadPath() {
                let mediaExists = FileManager.init().fileExists(atPath: downloadedAssetURL.path)
                return mediaExists
            }
        }else {
            // Media is present at asset's URL. This means asset was created out of the locally stored media. Thus, it is already downloaded.
            return true
        }
        
        return false
    }
    
    func downloadPath(create: Bool = false) -> URL? {
        
        guard let directory = self.url.absoluteString.sha256() else {
            return nil
        }
        
        guard let documentsDirectory: URL = FileManager.init().urls(for: FileManager.SearchPathDirectory.documentDirectory, in: FileManager.SearchPathDomainMask.userDomainMask).last else {
            return nil
        }
        
        let filename = "media.mp4"
        let directoryURL = documentsDirectory.appendingPathComponent(directory)
        
        if create {
            do {
                try FileManager.init().createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }catch let error as NSError {
                print("Failed to create asset's download path with error: \(error.localizedDescription)")
            }
        }
        
        let mediaURL = directoryURL.appendingPathComponent(filename)
        
        return mediaURL
    }
}

extension String {
    func sha256() -> String? {
        
        if let stringData = self.data(using: String.Encoding.utf8) {
            if let hash = stringData.sha256() {
                return hash.base64EncodedString()
            }
        }
        
        return nil
    }
}

extension Data {
    func sha256() -> Data? {
        
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0, CC_LONG(self.count), &hash)
        }
        return Data(bytes: hash)
        
    }

}
